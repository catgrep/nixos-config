# SPDX-License-Identifier: GPL-3.0-or-later

# The systemd unit-monitoring alert rules, generated once so the production
# Prometheus config (modules/gateway/prometheus.nix) and the
# service-alert-rules flake check exercise the exact same PromQL rather than
# two copies that can drift apart. `hosts` only exists because
# SystemdMonitoringDataMissing needs one absent() rule per host; every other
# rule is host-generic and reads the `host` label off the scraped series.
{ pkgs, hosts }:

let
  inherit (pkgs) lib;

  # Prefixes every non-empty line of `text` with `n` spaces, without
  # disturbing blank separator lines. Needed because the per-host block below
  # is its own indented string with its own independent dedent baseline; this
  # is what lines its output up with the hand-written rules around it.
  indentLines =
    n: text:
    let
      pad = lib.concatStrings (lib.genList (_: " ") n);
    in
    lib.concatMapStringsSep "\n" (line: if line == "" then "" else pad + line) (
      lib.splitString "\n" text
    );

  perHostMissingRules = indentLines 6 (
    lib.concatMapStringsSep "\n" (host: ''
      - alert: SystemdMonitoringDataMissing
        expr: absent(up{job="systemd", host="${host}"})
        for: 10m
        labels:
          severity: warning
          family: absent-systemd
        annotations:
          summary: "No systemd exporter scrape recorded for host ${host}; unit-level alerts for this host cannot fire"

      - alert: SystemdMonitoringDataMissing
        expr: absent(up{job="node-exporter", host="${host}"})
        for: 10m
        labels:
          severity: warning
          family: absent-node-exporter
        annotations:
          summary: "No node-exporter scrape recorded for host ${host}; the monitoring policy for this host cannot be confirmed"
    '') hosts
  );
in
pkgs.writeText "service-alert-rules.yml" ''
  # Every unit-level alert below (SystemdUnitFailed, SystemdServiceCrashLooping,
  # SystemdServiceNotActive) carries the same three "and on (host)" guards
  # before it is allowed to fire: a healthy systemd scrape, a healthy
  # node-exporter scrape, and a collected monitoring policy
  # (homelab_systemd_monitoring_info). This is a collection-eligibility
  # requirement, not a redundant health check -- the `unless` exclusion that
  # follows only means something once collection is known-good, so an
  # exclusion can be trusted to have actually been evaluated against real
  # data. Excluding only on up == 0 is not enough: an absent `up` series (the
  # scrape target gone entirely, not merely down) must also block fan-out,
  # because there is nothing left to apply an exclusion against. That gap is
  # exactly what SystemdMonitoringDataMissing exists to catch instead.
  groups:
    - name: service-monitoring
      rules:
        - alert: SystemdUnitFailed
          expr: |
            (systemd_unit_state{job="systemd", name=~".+\\.service", state="failed"} == 1)
            and on (host) (up{job="systemd"} == 1)
            and on (host) (up{job="node-exporter"} == 1)
            and on (host) (homelab_systemd_monitoring_info == 1)
            unless on (host, name) (homelab_systemd_alert_excluded == 1)
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Unit {{ $labels.name }} failed on {{ $labels.host }}"

        # increase() over a counter is an extrapolated estimate derived from
        # the samples inside the window, not an exact restart count -- the
        # threshold below is deliberately approximate, not a precise tally.
        - alert: SystemdServiceCrashLooping
          expr: |
            (increase(systemd_service_restart_total{job="systemd"}[10m]) > 3)
            and on (host) (up{job="systemd"} == 1)
            and on (host) (up{job="node-exporter"} == 1)
            and on (host) (homelab_systemd_monitoring_info == 1)
            unless on (host, name) (homelab_systemd_alert_excluded == 1)
          labels:
            severity: critical
          annotations:
            summary: "Unit {{ $labels.name }} on {{ $labels.host }} shows frequent automatic restarts; it may be retrying a failed startup"

        # The unless-arm covers three cases at once: the expected unit is
        # inactive, it is stuck mid-transition (its active-state series is
        # present but reads 0), or it is absent from telemetry entirely. The
        # count-by-host and-arm suppresses this alert only when ALL
        # systemd_unit_state series for the host have vanished -- that total
        # loss belongs to SystemdMonitoringDataMissing below, not here.
        - alert: SystemdServiceNotActive
          expr: |
            (
              (homelab_systemd_expected_running == 1)
              unless on (host, name) (systemd_unit_state{job="systemd", state="active"} == 1)
            )
            and on (host) (count by (host) (systemd_unit_state{job="systemd"}) > 0)
            and on (host) (up{job="systemd"} == 1)
            and on (host) (up{job="node-exporter"} == 1)
            and on (host) (homelab_systemd_monitoring_info == 1)
            unless on (host, name) (homelab_systemd_alert_excluded == 1)
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "Expected-running unit {{ $labels.name }} on {{ $labels.host }}: activity cannot be confirmed; missing telemetry does not prove the service is stopped"

        # The rules below share an alertname on purpose (Prometheus allows
        # it) -- they all mean "collection itself is broken", and they must
        # keep firing even when every unit-level alert above is silenced by
        # its eligibility guards, because that silence is exactly the
        # symptom they exist to surface. HostDown already owns plain up == 0
        # and is not duplicated here.
        #
        # Each variant carries a distinct `family` label. Without it, cases
        # (a) and (b) below both key off the identical `up{job="systemd"}`
        # base vector, and a host that loses both metric families at once
        # would make both rules produce the exact same output series --
        # which Prometheus refuses to evaluate, taking the whole rule group
        # down with it. `family` guarantees the variants can never collide.

        - alert: SystemdMonitoringDataMissing
          expr: (up{job="systemd"} == 1) unless on (host) (count by (host) (systemd_unit_state) > 0)
          for: 10m
          labels:
            severity: warning
            family: unit-state
          annotations:
            summary: "systemd exporter scrape is healthy but no systemd_unit_state series are being collected; unit-state alerts cannot fire"

        # Restart-data loss must alert on its own without disabling
        # SystemdUnitFailed -- that rule carries no restart-family guard, so
        # a failed unit still pages even while this fires.
        - alert: SystemdMonitoringDataMissing
          expr: (up{job="systemd"} == 1) unless on (host) (count by (host) (systemd_service_restart_total) > 0)
          for: 10m
          labels:
            severity: warning
            family: restart-total
          annotations:
            summary: "systemd exporter scrape is healthy but no systemd_service_restart_total series are being collected; crash-loop detection cannot fire"

        - alert: SystemdMonitoringDataMissing
          expr: (up{job="node-exporter"} == 1) unless on (host) (homelab_systemd_monitoring_info == 1)
          for: 10m
          labels:
            severity: warning
            family: policy
          annotations:
            summary: "node-exporter scrape is healthy but the systemd monitoring policy textfile is missing; unit alerts cannot apply exclusions or expectations"

  ${perHostMissingRules}
''
