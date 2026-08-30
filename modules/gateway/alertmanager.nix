# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

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
  # The other two mail paths on this network are narrower than they look and
  # neither covers this: the storage host mails on a unit that *failed*, which
  # is the loud case within seconds, and Grafana mails on its own separate
  # rules. What arrives here is the quiet case -- a job that stopped running, so
  # nothing failed and nothing was stamped.
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
    };
  };

  # Rendered by the secret manager as root, which is what systemd needs: the
  # unit runs under a transient user that could not read a file owned by a
  # named one, and EnvironmentFile is read before privileges are dropped.
  #
  # The value is the same Gmail application password Grafana already sends
  # through, referenced rather than duplicated so there is one credential to
  # rotate rather than two that can disagree.
  sops.templates."alertmanager.env" = {
    content = ''
      ALERTMANAGER_SMTP_PASSWORD=${config.sops.placeholder.grafana_smtp_password}
    '';
    mode = "0400";
  };
}
