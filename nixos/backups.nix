{
  config,
  pkgs,
  ...
}: let
  mirroredRepoPath = "/mnt/downloads-2t/Backups/borg/mirrored";
  mirroredSourcePath = "/mnt/mirrored";
  # The bucket name is a `pulumi stack output` in `../remote`, hand-placed here.
  mirroredBucketNamePath = "/etc/nixos/secrets/borg-s3-bucket-name";
  mirroredBorgPassphrasePath = config.sops.secrets.borg-passphrase.path;
  mirroredRcloneConfPath = config.sops.secrets.rclone-conf.path;
in {
  sops.secrets = {
    borg-passphrase = {};
    rclone-conf = {};
  };

  services.borgbackup = {
    jobs = {
      mirrored = {
        paths = [mirroredSourcePath];
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
            --stats 1m \
            || echo "Warning: S3 upload failed, but local backup completed successfully"
        '';
      };
    };
  };
}
