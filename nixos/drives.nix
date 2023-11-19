{...}: let
  mirroredStorageIdentifier = "mirrored";
  mirroredStorageMount = "/mnt/mirrored";
  downloadsMount = "/mnt/downloads";
in {
  # The main OS drive nvme0n1 is not handled by disko.
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = mirroredStorageIdentifier;
              };
            };
          };
        };
      };
      sdb = {
        type = "disk";
        device = "/dev/sdb";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = mirroredStorageIdentifier;
              };
            };
          };
        };
      };
      nvme1n1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            media = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = downloadsMount;
              };
            };
          };
        };
      };
    };
    mdadm = {
      "${mirroredStorageIdentifier}" = {
        type = "mdadm";
        level = 1;
        content = {
          type = "gpt";
          partitions = {
            primary = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = mirroredStorageMount;
              };
            };
          };
        };
      };
    };
  };
}
