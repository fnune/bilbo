{
  config,
  lib,
  pkgs,
  notify,
  ...
}: let
  mirrored-storage = "mirrored";
  mirrored-storage-mount = "/mnt/mirrored";
  downloads-1t-mount = "/mnt/downloads-1t";
  downloads-2t-mount = "/mnt/downloads-2t";

  surveillance-storage = "${downloads-2t-mount}/frigate";
  document-storage = "${mirrored-storage-mount}/papra";

  archive = "${mirrored-storage-mount}/archive";

  libraries = {
    movies = "${downloads-1t-mount}/Movies";
    series = "${downloads-2t-mount}/Series";
    books = "${downloads-1t-mount}/Books";
  };

  ownedByServices = [surveillance-storage document-storage config.services.immich.mediaLocation];

  outsideServiceOwned = "\\( ${lib.concatMapStringsSep " -o " (path: "-path ${path}") ownedByServices} \\) -prune -o";

  claimForFausto = mount: ''
    find ${mount} ${outsideServiceOwned} -print0 \
      | xargs --null --no-run-if-empty chown --no-dereference fausto:users
    find ${mount} ${outsideServiceOwned} ! -type l -print0 \
      | xargs --null --no-run-if-empty chmod 775
  '';

  mdadmEvent = pkgs.writeShellScript "mdadm-event" ''
    event=$1
    array=$2
    disk=''${3:-}
    case "$event" in
      Fail | FailSpare | DegradedArray | DeviceDisappeared | SparesMissing | TestMessage)
        ${notify}/bin/notify "RAID $event on $array" "mdadm reported $event on $array $disk" urgent
        ;;
    esac
  '';
in {
  _module.args = {
    mounts = {
      downloads-1t = downloads-1t-mount;
      downloads-2t = downloads-2t-mount;
      mirrored = mirrored-storage-mount;
    };
    inherit libraries;
  };

  systemd.tmpfiles.rules = map (folder: "d ${folder} 0775 fausto users -") (builtins.attrValues libraries ++ [archive]);

  boot.swraid.mdadmConf = "PROGRAM ${mdadmEvent}";

  systemd.services.adjustMountPoints = {
    description = "Adjust mount point permissions";
    wantedBy = ["multi-user.target"];
    before = ["multi-user.target"];
    script = lib.concatMapStrings claimForFausto [
      downloads-1t-mount
      downloads-2t-mount
      mirrored-storage-mount
    ];
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
