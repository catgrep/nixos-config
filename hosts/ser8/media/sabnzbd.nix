# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

{
  services.sabnzbd = {
    enable = true;
    configFile = "/var/lib/sabnzbd/sabnzbd.ini";
  };

  sops = {
    secrets = {
      "sabnzbd_api_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_nzb_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_usenet_username" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_usenet_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_usenet_provider" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };

    templates."sabnzbd.ini" = {
      content = ''
        [misc]
        permissions = 2775
        umask = 002
        host = 0.0.0.0
        port = 8085
        api_key = ${config.sops.placeholder."sabnzbd_api_key"}
        nzb_key = ${config.sops.placeholder."sabnzbd_nzb_key"}
        username = admin
        password = ${config.sops.placeholder."sabnzbd_admin_password"}
        download_dir = /mnt/media/downloads/usenet/incomplete
        complete_dir = /mnt/media/downloads/usenet/complete/default
        script_dir =
        log_dir = /var/lib/sabnzbd/logs
        admin_dir = /var/lib/sabnzbd/admin
        nzb_backup_dir = /var/lib/sabnzbd/backup
        dirscan_dir =
        auto_browser = 0
        rating_enable = 0
        enable_https = 0
        https_port = 9090
        bandwidth_max =
        refresh_rate = 0
        cache_limit = 1G
        pause_on_post_processing = 0
        ignore_samples = 0
        deobfuscate_final_filenames = 1
        auto_sort = 0
        propagation_delay = 0
        folder_rename = 1
        direct_unpack = 0
        no_penalties = 0
        par_option = 1
        pre_check = 1
        nice =
        ionice =
        win_process_prio = 3
        enable_all_par = 0
        top_only = 0
        safe_postproc = 1
        pause_on_pwrar = 1
        enable_unrar = 1
        enable_7zip = 1
        enable_filejoin = 1
        enable_tsjoin = 1
        overwrite_files = 0
        ignore_unrar_dates = 0
        backup_for_duplicates = 1
        empty_postproc = 0
        wait_for_dfolder = 0
        rss_rate = 60
        ampm = 0
        start_paused = 0
        preserve_paused_state = 0
        enable_par_cleanup = 1
        process_unpacked_par2 = 1
        enable_recursive = 1
        flat_unpack = 0
        script_can_fail = 0
        new_nzb_on_failure = 0
        unwanted_extensions =
        action_on_unwanted_extensions = 0
        unwanted_extensions_mode = 0
        sanitize_safe = 0
        replace_illegal = 1
        max_art_tries = 3
        max_art_opt = 1
        load_balancing = 2
        fail_hopeless_jobs = 1
        fast_fail = 1
        auto_disconnect = 1
        pre_script =
        end_queue_script =
        no_dupes = 0
        no_series_dupes = 0
        series_propercheck = 1
        no_smart_dupes = 0
        smart_dupes_whitelist =
        dupes_propercheck = 1
        pause_on_queue_finish = 0
        history_retention = 0
        enable_https_verification = 1
        quota_size =
        quota_day =
        quota_resume = 0
        quota_period = m
        pre_check_opt = 1

        [servers]
        [[${config.sops.placeholder."sabnzbd_usenet_provider"}]]
        name = ${config.sops.placeholder."sabnzbd_usenet_provider"}
        displayname = ${config.sops.placeholder."sabnzbd_usenet_provider"}
        host = ${config.sops.placeholder."sabnzbd_usenet_provider"}
        port = 563
        timeout = 120
        username = ${config.sops.placeholder."sabnzbd_usenet_username"}
        password = ${config.sops.placeholder."sabnzbd_usenet_password"}
        connections = 100
        ssl = 1
        ssl_verify = 2
        ssl_ciphers =
        enable = 1
        required = 0
        optional = 0
        retention = 0
        send_group = 0
        priority = 0
        notes =

        [categories]
        [[tv]]
        name = tv
        order = 0
        pp = 3
        script = Default
        dir = /mnt/media/downloads/usenet/complete/tv
        newzbin =
        priority = 0

        [[movies]]
        name = movies
        order = 1
        pp = 3
        script = Default
        dir = /mnt/media/downloads/usenet/complete/movies
        newzbin =
        priority = 0

        [[prowlarr]]
        name = *
        order = 2
        pp = 3
        script = Default
        dir = /mnt/media/downloads/usenet/complete/prowlarr
        newzbin =
        priority = 0

        [[*]]
        name = *
        order = 2
        pp = 3
        script = Default
        dir = /mnt/media/downloads/usenet/complete/default
        newzbin =
        priority = 0
      '';
      owner = "sabnzbd";
      group = config.services.sabnzbd.group;
      mode = "0600";
    };
  };

  systemd.services.media-config = {
    before = lib.mkOrder 550 [ "sabnzbd.service" ];
    script = lib.mkOrder 600 ''
      configure_arr sabnzbd ${config.sops.templates."sabnzbd.ini".path}
    '';
  };
}
