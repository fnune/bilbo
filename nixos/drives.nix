{...}: let
  mirrored-storage = "mirrored";
  mirrored-storage-mount = "/mnt/mirrored";
  downloads-1t-mount = "/mnt/downloads-1t";
  downloads-2t-mount = "/mnt/downloads-2t";
in {
  fileSystems = {
    "/mnt/downloads-1t" = {
      device = "/dev/disk/by-partlabel/disk-main-downloads-1t";
      fsType = "ext4";
      options = ["defaults" "uid=1000" "gid=100" "umask=002"];
    };
    "/mnt/downloads-2t" = {
      device = "/dev/disk/by-partlabel/disk-downloads-2t-media";
      fsType = "ext4";
      options = ["defaults" "uid=1000" "gid=100" "umask=002"];
    };
    "/mnt/mirrored" = {
      device = "/dev/disk/by-id/md-name-any:mirrored-part1";
      fsType = "ext4";
      options = ["defaults" "uid=1000" "gid=100" "umask=002"];
    };
  };
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
            downloads-1t = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = downloads-1t-mount;
              };
            };
          };
        };
      };
      downloads-2t = {
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
                mountpoint = downloads-2t-mount;
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
                name = mirrored-storage;
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
                name = mirrored-storage;
              };
            };
          };
        };
      };
    };
    mdadm = {
      "${mirrored-storage}" = {
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
                mountpoint = mirrored-storage-mount;
              };
            };
          };
        };
      };
    };
  };
}
