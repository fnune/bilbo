{
  config,
  lib,
  pkgs,
  ...
}: let
  mirroredRepoPath = "/mnt/downloads-2t/Backups/borg/mirrored";
  inherit (config.services) jellyfin radarr sonarr bazarr;
  backedUpPaths = [
    "/mnt/mirrored"
    config.services.home-assistant.configDir
    config.services.zigbee2mqtt.dataDir
    "/var/lib/pincho"
    jellyfin.dataDir
    radarr.dataDir
    sonarr.dataDir
    bazarr.dataDir
    # Prowlarr uses DynamicUser, so /var/lib/prowlarr is a symlink, which Borg would back up as just a link.
    # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#DynamicUser=
    "/var/lib/private/prowlarr"
    config.services.seerr.configDir
  ];
  rebuildableOnTheirOwn = [
    jellyfin.logDir
    "${jellyfin.dataDir}/transcodes"
    "${radarr.dataDir}/logs"
    "${radarr.dataDir}/MediaCover"
    "${sonarr.dataDir}/logs"
    "${sonarr.dataDir}/MediaCover"
    "${bazarr.dataDir}/log"
    "/var/lib/private/prowlarr/logs"
  ];
  mirroredBucketNamePath = config.sops.secrets.borg-s3-bucket-name.path;
  mirroredBorgPassphrasePath = config.sops.secrets.borg-passphrase.path;
  mirroredRcloneConfPath = config.sops.secrets.rclone-conf.path;

  statusDir = "/var/lib/backup-status";
  lockWaitSeconds = toString (6 * 60 * 60);
  freshness = {
    local = {
      stamp = "${statusDir}/mirrored-last-success";
      unit = "borgbackup-job-mirrored.service";
      intervalDays = 1;
    };
    offsite = {
      stamp = "${statusDir}/mirrored-offsite-last-success";
      unit = "borgbackup-offsite-mirrored.service";
      # Weekly: Deep Archive charges for deleted files as if kept 180 days.
      # https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html
      intervalDays = 7;
    };
  };
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
        exclude = rebuildableOnTheirOwn;
        repo = mirroredRepoPath;
        startAt = "daily";
        inhibitsSleep = false;
        compression = "auto,lzma";
        extraArgs = ["--lock-wait" lockWaitSeconds];
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
          if [ "$exitStatus" = 0 ]; then
            touch ${freshness.local.stamp}
          fi
        '';
        readWritePaths = [statusDir];
      };
    };
  };

  systemd.tmpfiles.rules = ["d ${statusDir} 0755 root root -"];

  systemd.services.borgbackup-offsite-mirrored = {
    description = "Mirror the mirrored Borg repository to S3 Deep Archive";
    startAt = "Sun 04:00";
    after = ["network-online.target" freshness.local.unit];
    wants = ["network-online.target"];
    unitConfig.RequiresMountsFor = [mirroredRepoPath];
    environment.BORG_PASSCOMMAND = "cat ${mirroredBorgPassphrasePath}";
    serviceConfig = {
      Type = "oneshot";
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
    script = ''
      BUCKET_NAME=$(cat ${mirroredBucketNamePath})
      ${pkgs.borgbackup}/bin/borg with-lock --lock-wait ${lockWaitSeconds} ${mirroredRepoPath} \
        ${pkgs.rclone}/bin/rclone sync ${mirroredRepoPath} "aws-glacier:$BUCKET_NAME/mirrored" \
          --config ${mirroredRcloneConfPath} \
          --stats 1m
      touch ${freshness.offsite.stamp}
    '';
  };
  systemd.timers.borgbackup-offsite-mirrored.timerConfig.Persistent = true;

  systemd.services.backup-never-run = {
    description = "Start any backup that has never succeeded on this machine";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      units=()
      ${lib.concatMapStrings (backup: ''
        [ -e ${backup.stamp} ] || units+=(${backup.unit})
      '') (builtins.attrValues freshness)}
      if [ ''${#units[@]} -gt 0 ]; then
        ${pkgs.systemd}/bin/systemctl start --no-block "''${units[@]}"
      fi
    '';
  };

  systemd.services.backup-freshness = {
    description = "Check that the mirrored backup and its off-site copy succeeded recently";
    startAt = "daily";
    serviceConfig.Type = "oneshot";
    script =
      lib.concatStrings (lib.mapAttrsToList (name: backup: let
          maxAgeDays = toString (backup.intervalDays + 1);
        in ''
          if [ -z "$(${pkgs.findutils}/bin/find ${backup.stamp} -mtime -${maxAgeDays} 2>/dev/null)" ]; then
            echo "No successful ${name} backup of the mirrored repository in the last ${maxAgeDays} days."
            stale=1
          fi
        '')
        freshness)
      + ''
        exit ''${stale:-0}
      '';
  };
}
