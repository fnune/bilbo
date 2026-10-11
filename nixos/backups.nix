{
  config,
  pkgs,
  ...
}: let
  mirroredRepoPath = "/mnt/downloads-2t/Backups/borg/mirrored";
  backedUpPaths = [
    "/mnt/mirrored"
    config.services.home-assistant.configDir
    config.services.zigbee2mqtt.dataDir
    "/var/lib/pincho"
    config.services.seerr.configDir
  ];
  mirroredBucketNamePath = config.sops.secrets.borg-s3-bucket-name.path;
  mirroredBorgPassphrasePath = config.sops.secrets.borg-passphrase.path;
  mirroredRcloneConfPath = config.sops.secrets.rclone-conf.path;

  statusDir = "/var/lib/backup-status";
  lastSuccess = "${statusDir}/mirrored-last-success";
  backupIntervalDays = 7;
  maxAgeDays = backupIntervalDays + 1;
in {
  sops.secrets = {
    borg-passphrase = {};
    borg-s3-bucket-name = {};
    rclone-conf = {};
  };

  services.borgbackup = {
    jobs = {
      mirrored = {
        paths = backedUpPaths;
        repo = mirroredRepoPath;
        startAt = "weekly";
        inhibitsSleep = false;
        compression = "auto,lzma";
        extraCreateArgs = ["--stats" "--progress"];
        group = "users";
        encryption = {
          mode = "repokey";
          passCommand = "cat ${mirroredBorgPassphrasePath}";
        };
        prune.keep = {
          daily = 7;
          weekly = 4;
          monthly = 6;
          yearly = 3;
        };
        postHook = ''
          BUCKET_NAME=$(cat ${mirroredBucketNamePath})
          ${pkgs.rclone}/bin/rclone sync ${mirroredRepoPath} aws-glacier:$BUCKET_NAME/mirrored \
            --config ${mirroredRcloneConfPath} \
            --progress \
            --stats 1m
          if [ "$exitStatus" = 0 ]; then
            touch ${lastSuccess}
          fi
        '';
        readWritePaths = [statusDir];
      };
    };
  };

  systemd.tmpfiles.rules = ["d ${statusDir} 0755 root root -"];

  systemd.services.backup-freshness = {
    description = "Check that the mirrored backup succeeded recently";
    startAt = "daily";
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -z "$(${pkgs.findutils}/bin/find ${lastSuccess} -mtime -${toString maxAgeDays} 2>/dev/null)" ]; then
        echo "No successful backup of /mnt/mirrored in the last ${toString maxAgeDays} days."
        exit 1
      fi
    '';
  };
}
