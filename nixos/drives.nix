{...}: let
  mirrored-storage = "mirrored";
  mirrored-storage-mount = "/mnt/mirrored";
  downloads-1t-mount = "/mnt/downloads-1t";
  downloads-2t-mount = "/mnt/downloads-2t";
in {
  systemd.services.adjustMountPoints = {
    description = "Adjust mount point permissions";
    wantedBy = ["multi-user.target"];
    before = ["multi-user.target"];
    script = ''
      chown -R fausto:users /mnt/downloads-1t
      chown -R fausto:users /mnt/downloads-2t
      chown -R fausto:users /mnt/mirrored
      chmod 775 /mnt/downloads-1t
      chmod 775 /mnt/downloads-2t
      chmod 775 /mnt/mirrored
      mkdir -p /mnt/mirrored/nextcloud
      chown -R nextcloud:nextcloud /mnt/mirrored/nextcloud
    '';
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
