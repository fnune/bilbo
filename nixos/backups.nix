{
  bilboToolsCommand,
  config,
  lib,
  notify,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;
  backups = builtins.attrValues config.bilbo.backups;
  backedUpPaths = lib.concatMap (backup: backup.paths) backups;
  excludedPaths = lib.concatMap (backup: backup.exclude) backups;
  stoppedCopies = lib.concatMap (backup: lib.optional (backup.stopToCopy != null) backup.stopToCopy) backups;
  copyWhileStopped = {
    service,
    directory,
  }: ''
    (
      trap 'systemctl start ${service}.service' EXIT
      systemctl stop ${service}.service
      rm -rf ${directory}-snapshot
      cp --archive ${directory} ${directory}-snapshot
    )
  '';

  mirroredRepoPath = "/mnt/downloads-2t/Backups/borg/mirrored";
  mirroredStorage = "/mnt/mirrored";
  mirroredBucketNamePath = config.sops.secrets.borg-s3-bucket-name.path;
  mirroredBorgPassphrasePath = config.sops.secrets.borg-passphrase.path;
  mirroredRcloneConfPath = config.sops.secrets.rclone-conf.path;

  statusDir = "/var/lib/backup-status";

  sqliteSnapshots = "/var/lib/backup-sqlite-snapshots";
  sqliteExcludes = "${statusDir}/sqlite-excludes";
  busyTimeoutMilliseconds = 60 * 1000;
  skipIfMissing = path: "-${path}";
  # Borg copies files mid-write; SQLite's online backup gives a consistent copy without stopping the app.
  snapshotSqlite = pkgs.writeShellApplication {
    name = "snapshot-sqlite";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.sqlite];
    text = ''
      is_sqlite() {
        [ "$(head -c 15 "$1" | tr -d "\0")" = "SQLite format 3" ]
      }
      give_sidecars_back_to_app() { # A -wal or -shm created as root would lock the app out.
        for sidecar in "$1"-wal "$1"-shm "$1"-journal; do
          if [ -e "$sidecar" ]; then chown --reference "$1" "$sidecar"; fi
        done
      }

      find ${sqliteSnapshots} -mindepth 1 -delete
      : > ${sqliteExcludes}
      { find ${lib.escapeShellArgs backedUpPaths} -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) -print0 2>/dev/null || true; } |
        while IFS= read -r -d "" database; do
          is_sqlite "$database" || continue
          snapshot=${sqliteSnapshots}$database
          mkdir -p "$(dirname "$snapshot")"
          sqlite3 "$database" ".timeout ${toString busyTimeoutMilliseconds}" ".backup '$snapshot'"
          give_sidecars_back_to_app "$database"
          for file in "$database" "$database"-wal "$database"-shm "$database"-journal; do
            printf "pp:%s\n" "$file" >> ${sqliteExcludes}
          done
        done
    '';
  };
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
  options.bilbo.backups = mkOption {
    default = {};
    description = "What each service keeps in the daily backup, alongside all of /mnt/mirrored.";
    type = types.attrsOf (types.submodule {
      options = {
        paths = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Backed up daily. SQLite databases under them are backed up from a snapshot taken while the service runs.";
        };
        exclude = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Paths the service rebuilds on its own, such as logs and caches.";
        };
        stopToCopy = mkOption {
          default = null;
          description = "For data a live snapshot cannot read, such as an encrypted database: the service stops while directory is copied to <directory>-snapshot, which must sit under a backed-up path.";
          type = types.nullOr (types.submodule {
            options = {
              service = mkOption {type = types.str;};
              directory = mkOption {type = types.str;};
            };
          });
        };
      };
    });
  };

  config = {
    sops.secrets = {
      borg-passphrase = {};
      borg-s3-bucket-name = {};
      rclone-conf = {};
    };

    services.borgbackup = {
      jobs = {
        mirrored = {
          paths = [mirroredStorage sqliteSnapshots] ++ backedUpPaths;
          exclude = excludedPaths ++ map (copy: copy.directory) stoppedCopies;
          repo = mirroredRepoPath;
          startAt = "daily";
          inhibitsSleep = false;
          persistentTimer = true;
          compression = "auto,lzma";
          extraArgs = ["--lock-wait" (toString lockWaitSeconds)];
          extraCreateArgs = ["--stats" "--progress" "--exclude-from" sqliteExcludes];
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
          preHook = lib.concatLines ([(lib.getExe snapshotSqlite)] ++ map copyWhileStopped stoppedCopies);
          postHook = ''
            if [ "$exitStatus" = 0 ]; then
              touch ${freshness.local.stamp}
            fi
          '';
          readWritePaths = [statusDir sqliteSnapshots] ++ map (copy: dirOf copy.directory) stoppedCopies;
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d ${statusDir} 0755 root root -"
      "d ${sqliteSnapshots} 0700 root root -"
    ];

    systemd.services.borgbackup-job-mirrored.serviceConfig.ReadWritePaths = map skipIfMissing backedUpPaths; # SQLite writes to a WAL database's -shm even to read it.

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
        sqliteSnapshotPath = lib.removePrefix "/" sqliteSnapshots;
        sqlite = lib.getExe pkgs.sqlite;
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
  };
}
