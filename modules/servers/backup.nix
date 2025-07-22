{ config, lib, pkgs, ... }:

{
  # Install backup tools
  environment.systemPackages = with pkgs; [
    borgbackup
    restic
    rsync
  ];

  # Create backup user
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    home = "/var/lib/backup";
    createHome = true;
    shell = pkgs.bash;
  };

  users.groups.backup = {};

  # Backup script template (customize per host)
  environment.etc."backup/backup-script.sh" = {
    text = ''
      #!/bin/bash
      # Basic backup script template
      # Customize this per host in their specific configuration

      BACKUP_SOURCE="/home /etc /var/log"
      BACKUP_DEST="/mnt/backups"
      DATE=$(date +%Y-%m-%d_%H-%M-%S)

      echo "Starting backup at $DATE"

      # Add your backup commands here
      # Example: rsync -av $BACKUP_SOURCE $BACKUP_DEST/

      echo "Backup completed at $(date)"
    '';
    mode = "0755";
  };
}
