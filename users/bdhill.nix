# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # System user configuration
  systemConfig = {
    isNormalUser = true;
    description = "Bobby Hill";
    extraGroups = [
      "wheel"
      "networkmanager"
      "media"
      "render"
    ];
    uid = 1000;
    shell = pkgs.zsh;

    # SSH keys
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQWQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
    ];
  };

  # Home Manager configuration for user bdhill
  homeConfig = {
    home.username = "bdhill";
    home.homeDirectory = "/home/bdhill";
    home.stateVersion = "25.05";

    # User-specific packages (most system tools are in environment.systemPackages)
    home.packages = with pkgs; [
      # Personal utilities not needed system-wide
      tree
      rsync
      whois

      # Additional monitoring tools
      iotop
      iftop
    ];

    # Git configuration
    programs.git = {
      enable = true;
      userName = "catgrep";
      userEmail = "catgrep@sudomail.com";
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = false;
      };
    };

    # Zsh configuration (moved from system config)
    programs.zsh = {
      enable = true;

      # History configuration
      history = {
        size = 10000;
        save = 10000;
        ignoreDups = true;
        ignoreSpace = true;
      };

      # Shell initialization
      initContent = ''
        # Display fastfetch on login for interactive shells
        if [[ $- == *i* ]]; then
          fastfetch
        fi
      '';

      # Enable completion system
      enableCompletion = true;

      # Completion configuration
      completionInit = ''
        autoload -Uz compinit
        compinit

        # Completion styles
        zstyle ':completion:*' auto-description 'specify: %d'
        zstyle ':completion:*' completer _complete _ignored _correct _approximate
        zstyle ':completion:*' format '%d'
        zstyle ':completion:*' matcher-list "" "m:{[:lower:]}={[:upper:]}" "m:{[:lower:][:upper:]}={[:upper:][:lower:]}" "r:|[._-]=** r:|=** l:|=*"
        zstyle ':completion:*' max-errors 3 numeric
        zstyle ':completion:*' use-compctl true
      '';

      # Shell aliases
      shellAliases = {
        ll = "ls -alF";
        la = "ls -A";
        l = "ls -CF";
        grep = "grep --color=auto";
        fgrep = "fgrep --color=auto";
        egrep = "egrep --color=auto";
      };

      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "sudo"
          "docker"
          "systemd"
        ];
        theme = "robbyrussell";
      };
    };

    # Bash configuration (fallback shell)
    programs.bash = {
      enable = true;
      shellAliases = config.programs.zsh.shellAliases;
    };

    # Tmux configuration
    programs.tmux = {
      enable = true;
      baseIndex = 1;
      clock24 = true;
      escapeTime = 10;
      historyLimit = 5000;
      keyMode = "vi";
      newSession = true;
      prefix = "C-a";
      terminal = "tmux-256color";

      extraConfig = ''
        # Copy mode and clipboard
        set -s copy-command 'wl-copy'

        # Mouse support
        set -g mouse on
        bind -T copy-mode-vi WheelUpPane send-keys -X scroll-up
        bind -T copy-mode-vi WheelDownPane send-keys -X scroll-down

        # Key bindings
        # Last active window
        unbind l
        bind C-a last-window
        bind C-d detach-client
        unbind " "
        bind " " next-window
        bind C-" " next-window
        bind C-c new-window
        bind C-n next-window
        bind C-p previous-window
        bind v run "tmux show-buffer | wl-paste > /dev/null"

        # Highlighting the active window in status bar
        setw -g window-status-current-style bg=red
        set -g status-bg magenta
        set -g status-fg black

        # Add uptime to status bar
        set -g status-interval 5
        set -g status-right-length 100
        set -g status-right "#(uptime | awk -F 'up |,' '{print \"up\",$2}' | sed 's/  / /g') #(awk -F ' ' '{print $1,$2,$3}' /proc/loadavg) \"#H\" #(date '+%H:%M %a %m-%d')"
      '';
    };

    # Enable home-manager
    programs.home-manager.enable = true;
  };
}
