# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

let
  # The same address every other alerting path on this network already reaches,
  # rather than a second one to keep in step.
  recipient = "catgrep@sudomail.com";
  sender = "shadbangus@gmail.com";
in

{
  # Without this, a firing rule reaches nobody.
  #
  # That is worth stating plainly because the failure is entirely silent and
  # looks exactly like success: the rule evaluates, the alert shows as firing in
  # the API and on the rules page, and Prometheus then hands it to whatever is
  # listed under `alertmanagers` -- which, with nothing listed, is nowhere. A
  # staleness alert that has been "firing" for a day without a human hearing
  # about it is not an alert, it is a log line.
  #
  # The mail paths on the storage host are narrower than they look and neither
  # covers this: it mails on a unit that *failed*, which is the loud case
  # within seconds, and ZED mails on ZFS events. What arrives here is
  # everything a rule can express -- including the quiet case of a job that
  # stopped running, so nothing failed and nothing was stamped.
  services.prometheus.alertmanager = {
    enable = true;

    # Loopback only. Prometheus reaches it from this host, and the reverse
    # proxy is the way anything else gets in.
    listenAddress = "127.0.0.1";
    port = 9093;

    # The password must not be written here. The module renders this attrset
    # into the world-readable Nix store, so the value is a placeholder that
    # systemd substitutes at start from the environment file below. That
    # substitution is the module's own mechanism, not something bolted on.
    environmentFile = config.sops.templates."alertmanager.env".path;

    configuration = {
      global = {
        smtp_smarthost = "smtp.gmail.com:587";
        smtp_from = sender;
        smtp_auth_username = sender;
        smtp_auth_password = "$ALERTMANAGER_SMTP_PASSWORD";
        smtp_require_tls = true;
      };

      route = {
        receiver = "household";

        # Grouped by rule rather than by instance, so a night on which several
        # hosts go quiet at once produces one mail describing all of them
        # instead of one mail each.
        group_by = [ "alertname" ];

        # Half a minute to collect whatever else is about to fire, five minutes
        # before adding a newly firing instance to an open group.
        group_wait = "30s";
        group_interval = "5m";

        # Twice a day. The alerts this handles describe a job that has stopped
        # running, which is not a condition that improves on its own or that
        # anyone needs reminding of hourly, but it is one that must not be
        # forgotten if the first mail is missed.
        repeat_interval = "12h";
      };

      receivers = [
        {
          name = "household";
          email_configs = [
            {
              to = recipient;
              # Resolution mail included on purpose. These alerts fire on
              # absence, so "it started reporting again" is the message that
              # closes the loop and the one whose absence would leave someone
              # checking by hand.
              send_resolved = true;
            }
          ];
        }
      ];

      # Notification priority for the same unit is crash loop > failed >
      # expected-activity-missing: a crash loop already implies the unit is
      # unhealthy, and a hard failure already implies its expected activity
      # can't be confirmed, so the more specific diagnosis is the one that
      # should land in an inbox. `equal` on host+name means inhibition never
      # crosses hosts or units -- a crash loop on ser8's jellyfin.service
      # never silences a failure on firebat's caddy.service. This suppresses
      # notifications only; the underlying alerts stay firing and inspectable
      # on the rules page and in Grafana.
      inhibit_rules = [
        {
          source_matchers = [ ''alertname="SystemdServiceCrashLooping"'' ];
          target_matchers = [ ''alertname=~"SystemdUnitFailed|SystemdServiceNotActive"'' ];
          equal = [
            "host"
            "name"
          ];
        }
        {
          source_matchers = [ ''alertname="SystemdUnitFailed"'' ];
          target_matchers = [ ''alertname="SystemdServiceNotActive"'' ];
          equal = [
            "host"
            "name"
          ];
        }
      ];
    };
  };

  # The encrypted key in secrets/firebat.yaml is named grafana_smtp_password;
  # renaming it to match its consumer would mean re-encrypting the sops file
  # for no functional gain.
  sops.secrets.grafana_smtp_password = { };

  # Rendered by the secret manager as root, which is what systemd needs: the
  # unit runs under a transient user that could not read a file owned by a
  # named one, and EnvironmentFile is read before privileges are dropped.
  sops.templates."alertmanager.env" = {
    # SMTP credentials are substituted at service startup, not on config reload.
    restartUnits = [ "alertmanager.service" ];
    content = ''
      ALERTMANAGER_SMTP_PASSWORD=${config.sops.placeholder.grafana_smtp_password}
    '';
    mode = "0400";
  };

  homelab.monitoring.systemd.units = lib.mkIf config.services.prometheus.alertmanager.enable {
    "alertmanager.service".expectedRunning = true;
  };
}
