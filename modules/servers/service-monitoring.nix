# SPDX-License-Identifier: GPL-3.0-or-later

# Turns the homelab.monitoring.systemd.units declarations (see
# modules/common/service-monitoring.nix) into a static Prometheus textfile
# and owns the node exporter's textfile-directory flags and the systemd
# exporter's unit-collection scope, so both stay defined in exactly one
# place.
{ config, lib, ... }:

let
  units = config.homelab.monitoring.systemd.units;
  names = builtins.attrNames units;

  expectedRunningLines = map (name: ''homelab_systemd_expected_running{name="${name}"} 1'') (
    builtins.filter (name: units.${name}.enable && units.${name}.expectedRunning) names
  );

  excludedLines = map (name: ''homelab_systemd_alert_excluded{name="${name}"} 1'') (
    builtins.filter (name: !units.${name}.enable) names
  );

  # homelab_systemd_monitoring_info is always present, even with zero unit
  # declarations, so alert rules can require positive evidence that this
  # policy file was collected rather than treating an empty scrape the same
  # as a missing one.
  policyText = lib.concatStringsSep "\n" (
    [ "homelab_systemd_monitoring_info 1" ] ++ expectedRunningLines ++ excludedLines ++ [ "" ]
  );
in
{
  homelab.monitoring.systemd.units = lib.mkMerge [
    (lib.mkIf config.services.prometheus.exporters.node.enable {
      "prometheus-node-exporter.service".expectedRunning = true;
    })
    (lib.mkIf config.services.prometheus.exporters.systemd.enable {
      "prometheus-systemd-exporter.service".expectedRunning = true;
    })
    (lib.mkIf config.services.prometheus.exporters.process.enable {
      "prometheus-process-exporter.service".expectedRunning = true;
    })
  ];

  # environment.etc is store-backed, so activation atomically replaces this
  # file and its mtime always reads as "just deployed". Age-based textfile
  # staleness alerts must not be applied to it; use
  # homelab_systemd_monitoring_info's presence as the staleness signal instead.
  environment.etc."node-exporter-static/systemd-policy.prom".text = policyText;

  services.prometheus.exporters.node.extraFlags =
    lib.mkIf config.services.prometheus.exporters.node.enable
      [
        # /persist keeps textfile metrics across an impermanence rollback; a
        # rebooted host that lost them would read downstream as "the batch job
        # hasn't run since reboot". The path also sits outside any home
        # directory because this exporter runs with home directories hidden. The
        # writer of that first directory must declare the identical path, or the
        # mismatch produces no metrics and no error anywhere.
        "--collector.textfile.directory=/persist/var/lib/node-exporter-textfile"
        "--collector.textfile.directory=/etc/node-exporter-static"
      ];

  services.prometheus.exporters.systemd.extraFlags =
    lib.mkIf config.services.prometheus.exporters.systemd.enable
      [
        "--systemd.collector.unit-include=.+\\.service"
        "--systemd.collector.enable-restart-count"
      ];
}
