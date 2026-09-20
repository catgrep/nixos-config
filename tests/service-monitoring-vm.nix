# SPDX-License-Identifier: GPL-3.0-or-later

# Exercises modules/common/service-monitoring.nix and
# modules/servers/service-monitoring.nix in isolation, with real exporters
# scraping a real guest, so the flags and the generated policy file are
# proven against what Prometheus actually receives rather than against Nix
# evaluation alone.
{ pkgs }:

pkgs.testers.runNixOSTest {
  name = "service-monitoring-vm";

  nodes.machine =
    { pkgs, ... }:
    {
      # Only the schema and the collection machinery -- not the full
      # servers/ or common/ default.nix -- so this proves the two modules
      # work together without anything else in the closure quietly
      # supplying a flag or a default.
      imports = [
        ../modules/common/service-monitoring.nix
        ../modules/servers/service-monitoring.nix
      ];

      environment.systemPackages = [ pkgs.curl ];

      services.prometheus.exporters.node = {
        enable = true;
        port = 9100;
      };
      services.prometheus.exporters.systemd = {
        enable = true;
        port = 9558;
      };
      # process exporter left at its default (disabled): this is what proves
      # the mkIf-guarded expectedRunning declaration for it stays out of the
      # policy when the exporter it describes isn't even running.

      homelab.monitoring.systemd.units = {
        "steady.service".expectedRunning = true;
        "flappy.service".expectedRunning = true;
        "ignored.service".enable = false;
      };

      # A trivial long-running daemon. Declared expectedRunning, and later
      # stopped by hand to exercise the "went away" observable.
      systemd.services.steady = {
        description = "synthetic steady daemon for the service-monitoring VM test";
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };

      # Frigate-shaped: a failed startup precheck that restarts forever
      # rather than reaching a sustained failed state. StartLimitIntervalSec
      # = 0 disables systemd's own restart-limit shutoff, which is exactly
      # what makes this loop indefinite instead of self-resolving; the
      # 10-second cadence matches the observed Frigate retry interval.
      # Deliberately not wantedBy multi-user: the testScript starts it only
      # for the restart-count subtest and stops it afterwards, because a
      # unit churning through restarts is exactly the state a scrape can
      # race against, and every other subtest deserves a quiet machine.
      systemd.services.flappy = {
        description = "synthetic crash-loop daemon for the service-monitoring VM test";
        startLimitIntervalSec = 0;
        serviceConfig = {
          ExecStart = "${pkgs.coreutils}/bin/false";
          Restart = "always";
          RestartSec = 10;
        };
      };

      # A scheduled job. Not declared to the monitoring schema at all --
      # scheduled jobs need no declaration -- yet still collected by the
      # systemd exporter's broad unit-include.
      systemd.services."oneshot-job" = {
        description = "synthetic scheduled job for the service-monitoring VM test";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
      };

      # Declared with enable = false: the exclusion path, not the expected-
      # running path.
      systemd.services.ignored = {
        description = "synthetic excluded unit for the service-monitoring VM test";
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };

      # A sample textfile under the *other* directory the node exporter
      # reads. The single-owner flag design in service-monitoring.nix wires
      # two --collector.textfile.directory flags into one exporter, and a
      # regression that dropped one of them would still pass every
      # assertion about the generated policy file while silently losing
      # every metric written here.
      systemd.tmpfiles.rules = [
        "d /persist/var/lib/node-exporter-textfile 0755 root root -"
      ];
    };

  testScript = ''
    import re


    def restart_count(unit):
        metrics = machine.succeed("curl -sf http://localhost:9558/metrics")
        match = re.search(
            r'systemd_service_restart_total\{[^}]*name="'
            + re.escape(unit)
            + r'"[^}]*\}\s+([0-9.eE+-]+)',
            metrics,
        )
        return float(match.group(1)) if match else 0.0


    machine.wait_for_unit("multi-user.target")

    # Written here rather than via a tmpfiles f-rule because the exposition
    # format demands a trailing newline; tmpfiles writes its argument without
    # one, and the textfile collector then rejects the whole file with
    # "unexpected end of input stream".
    machine.succeed(
        "printf 'test_backup_metric 42\\n' "
        "> /persist/var/lib/node-exporter-textfile/sample.prom"
    )

    with subtest("the generated policy file contains exactly the declared units"):
        policy = machine.succeed("cat /etc/node-exporter-static/systemd-policy.prom")
        lines = {line for line in policy.splitlines() if line}
        expected = {
            "homelab_systemd_monitoring_info 1",
            'homelab_systemd_expected_running{name="steady.service"} 1',
            'homelab_systemd_expected_running{name="flappy.service"} 1',
            'homelab_systemd_expected_running{name="prometheus-node-exporter.service"} 1',
            'homelab_systemd_expected_running{name="prometheus-systemd-exporter.service"} 1',
            'homelab_systemd_alert_excluded{name="ignored.service"} 1',
        }
        assert lines == expected, (
            f"policy file diverged from the declared units: {lines ^ expected}"
        )

    with subtest("the node exporter serves both textfile directories"):
        machine.wait_for_open_port(9100)
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9100/metrics | "
            "grep -F 'homelab_systemd_monitoring_info 1' > /dev/null"
        )
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9100/metrics | "
            "grep -F 'homelab_systemd_expected_running{name=\"steady.service\"} 1' > /dev/null"
        )
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9100/metrics | grep -F 'test_backup_metric 42' > /dev/null"
        )

    with subtest("the systemd exporter's broad unit-include actually matches"):
        machine.wait_for_open_port(9558)
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9558/metrics | grep -E "
            "'systemd_unit_state\\{[^}]*name=\"steady.service\"[^}]*state=\"active\"[^}]*\\} 1' "
            "> /dev/null"
        )
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9558/metrics | grep 'name=\"oneshot-job.service\"' > /dev/null"
        )

    with subtest("the successful oneshot ends inactive rather than failed"):
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9558/metrics | grep -E "
            "'systemd_unit_state\\{[^}]*name=\"oneshot-job.service\"[^}]*state=\"inactive\"[^}]*\\} 1' "
            "> /dev/null"
        )
        machine.fail(
            "curl -sf http://localhost:9558/metrics | grep -E "
            "'systemd_unit_state\\{[^}]*name=\"oneshot-job.service\"[^}]*state=\"failed\"[^}]*\\} 1' "
            "> /dev/null"
        )

    with subtest("the crash loop's restarts are counted past the alert threshold"):
        # --no-block: the start job never completes, because the unit never
        # stays up. Four restarts at the 10-second cadence need ~40 seconds.
        machine.succeed("systemctl start --no-block flappy.service")
        retry(lambda last: restart_count("flappy.service") > 3, timeout_seconds=180)
        machine.succeed("systemctl stop flappy.service")

    with subtest("a manually stopped unit reads as active=0 on a fresh scrape"):
        machine.succeed("systemctl stop steady.service")
        machine.wait_until_succeeds(
            "curl -sf http://localhost:9558/metrics | grep -E "
            "'systemd_unit_state\\{[^}]*name=\"steady.service\"[^}]*state=\"active\"[^}]*\\} 0' "
            "> /dev/null"
        )
  '';
}
