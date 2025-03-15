{pkgs, ...}: let
  mirroredRepoPath = "/var/lib/borg/mirrored";
  mirroredSourcePath = "/mnt/mirrored";
  # Generate secrets by running `pulumi stack output` in `../remote`:
  mirroredBucketNamePath = "/etc/nixos/secrets/borg-s3-bucket-name";
  mirroredBorgPassphrasePath = "/etc/nixos/secrets/borg-passphrase";
  mirroredRcloneConfPath = "/etc/nixos/secrets/rclone.conf";
in {
  services.borgbackup = {
    jobs = {
      mirrored = {
        paths = [mirroredSourcePath];
        repo = mirroredRepoPath;
        startAt = "weekly";
        inhibitsSleep = false;
        compression = "auto,lzma";
        extraCreateArgs = ["--stats"];
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
            --storage-class=DEEP_ARCHIVE \
            || echo "Warning: S3 upload failed, but local backup completed successfully"
        '';
      };
    };
  };
}
