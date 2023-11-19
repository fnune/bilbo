{...}: let
  mirroredStorageIdentifier = "mirrored";
  mirroredStorageMount = "/mnt/mirrored";
  downloadsSmallMount = "/mnt/downloads-sm";
  downloadsLargeMount = "/mnt/downloads-lg";
in {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              size = "16G";
              content = {
                type = "swap";
                randomEncryption = true;
                resumeDevice = true;
              };
            };
            root = {
              size = "128G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            downloadsSmall = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = downloadsSmallMount;
              };
            };
          };
        };
      };
      downloadsLarge = {
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
                mountpoint = downloadsLargeMount;
              };
            };
          };
        };
      };
      mirror1 = {
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
      mirror2 = {
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
    };
    mirror = {
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
