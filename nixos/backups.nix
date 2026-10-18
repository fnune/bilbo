{
  bilboToolsCommand,
  config,
  lib,
  notify,
  pkgs,
  ...
}: let
  mirroredRepoPath = "/mnt/downloads-2t/Backups/borg/mirrored";
  inherit (config.services) jellyfin radarr sonarr bazarr;
  backedUpPaths = [
    "/mnt/mirrored"
    config.services.home-assistant.configDir
    config.services.zigbee2mqtt.dataDir
    "/var/lib/tashi"
    "/var/lib/shmups"
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
  lockWaitSeconds = 6 * 60 * 60;
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
  restoreTest = {
    description,
    startAt,
    command,
    secrets,
    settings,
  }: {
    inherit description startAt;
    after = ["network-online.target"];
    wants = ["network-online.target"];
    unitConfig.RequiresMountsFor = [mirroredRepoPath];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = bilboToolsCommand command settings;
      LoadCredential = map (secret: "${secret}:${config.sops.secrets.${secret}.path}") secrets;
      Nice = 10;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
  };
  remoteSample = {
    rclone = lib.getExe pkgs.rclone;
    remote = "aws-glacier";
    prefix = "mirrored";
    sampleFile = "${statusDir}/restore-sample";
  };
  quarterly = day: "*-01,04,07,10-${day} 10:00:00";
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
        persistentTimer = true;
        compression = "auto,lzma";
        extraArgs = ["--lock-wait" (toString lockWaitSeconds)];
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
      ${pkgs.borgbackup}/bin/borg with-lock --lock-wait ${toString lockWaitSeconds} ${mirroredRepoPath} \
        ${pkgs.rclone}/bin/rclone sync ${mirroredRepoPath} "aws-glacier:$BUCKET_NAME/mirrored" \
          --config ${mirroredRcloneConfPath} \
          --stats 1m
      touch ${freshness.offsite.stamp}
    '';
  };

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

  systemd.services.backup-restore-check-local = restoreTest {
    description = "Verify the local Borg repository and restore a few files from it";
    startAt = "*-*-02 10:00:00";
    command = "restore-check-local";
    secrets = ["borg-passphrase"];
    settings = {
      borg = lib.getExe' pkgs.borgbackup "borg";
      repository = mirroredRepoPath;
      inherit lockWaitSeconds;
      samplePath = "mnt/mirrored/immich/library";
      maxFileBytes = 200 * 1000 * 1000;
      notify = lib.getExe notify;
      root = "/";
    };
  };

  systemd.services.backup-restore-start-remote = restoreTest {
    description = "Thaw a random sample of the off-site repository from Deep Archive";
    startAt = quarterly "08";
    command = "restore-start-remote";
    secrets = ["borg-s3-bucket-name" "rclone-conf"];
    settings =
      remoteSample
      // {
        sampleBytes = 10 * 1000 * 1000 * 1000;
        availableDays = 7;
      };
  };

  systemd.services.backup-restore-check-remote = restoreTest {
    description = "Compare the thawed off-site sample with the local repository";
    startAt = quarterly "11";
    command = "restore-check-remote";
    secrets = ["borg-s3-bucket-name" "rclone-conf"];
    settings =
      remoteSample
      // {
        repository = mirroredRepoPath;
        notify = lib.getExe notify;
      };
  };

  systemd.timers = lib.genAttrs ["borgbackup-offsite-mirrored" "backup-restore-check-local" "backup-restore-start-remote" "backup-restore-check-remote"] (_: {
    timerConfig.Persistent = true;
  });
}
