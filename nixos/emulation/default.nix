{
  config,
  lib,
  pkgs,
  ...
}: let
  base = "/mnt/downloads-2t/Emulation";
  user = "fausto";
  group = "users";

  systems = import ./systems.nix;

  layouts = {
    emudeck-steamos = import ./layouts/emudeck-steamos.nix;
    nextui = import ./layouts/nextui.nix;
  };

  layoutDevicePaths = {
    emudeck-steamos = {
      roms = "roms";
      saves = "saves";
      bios = "bios";
    };
    nextui = {
      roms = "Roms";
      saves = "Saves";
      bios = "Bios";
    };
  };

  targets = {
    feanor = {
      layout = "emudeck-steamos";
      systems = systems;
    };
  };

  dir = path: "d \"${path}\" 0755 ${user} ${group} -";

  mkTargetDirs = name: cfg: let
    layout = layouts.${cfg.layout};
    romSystems = builtins.filter (s: layout.romFolder s != null) cfg.systems;
    saveCores = lib.unique (builtins.filter (x: x != null) (map layout.saveFolder cfg.systems));
    biosSystems = builtins.filter (s: layout.biosFolder s != null) cfg.systems;
  in
    [
      (dir "${base}/_targets/${name}")
      (dir "${base}/_targets/${name}/roms")
      (dir "${base}/_targets/${name}/saves")
      (dir "${base}/_targets/${name}/bios")
    ]
    ++ map (s: dir "${base}/_targets/${name}/roms/${layout.romFolder s}") romSystems
    ++ map (c: dir "${base}/_targets/${name}/saves/${c}") saveCores
    ++ map (s: dir "${base}/_targets/${name}/bios/${layout.biosFolder s}") biosSystems;

  mkTargetMounts = name: cfg: let
    layout = layouts.${cfg.layout};
    romSystems = builtins.filter (s: layout.romFolder s != null) cfg.systems;
    saveCores = lib.unique (builtins.filter (x: x != null) (map layout.saveFolder cfg.systems));
    biosSystems = builtins.filter (s: layout.biosFolder s != null) cfg.systems;
  in
    (map (s: {
      name = "${base}/_targets/${name}/roms/${layout.romFolder s}";
      value = {
        device = "${base}/roms/${s}";
        options = ["bind"];
      };
    }) romSystems)
    ++ (map (c: {
      name = "${base}/_targets/${name}/saves/${c}";
      value = {
        device = "${base}/saves/${c}";
        options = ["bind"];
      };
    }) saveCores)
    ++ (map (s: {
      name = "${base}/_targets/${name}/bios/${layout.biosFolder s}";
      value = {
        device = "${base}/bios/${s}";
        options = ["bind"];
      };
    }) biosSystems);

  baseBiosSystems = lib.unique (
    lib.concatMap (cfg:
      builtins.filter (s: (layouts.${cfg.layout}).biosFolder s != null) cfg.systems
    ) (lib.attrValues targets)
  );

  baseSaveDirs = lib.unique (
    builtins.filter (x: x != null)
    (lib.concatMap (cfg: map (layouts.${cfg.layout}).saveFolder cfg.systems) (lib.attrValues targets))
  );

  mkSetupScript = name: cfg: let
    device = layoutDevicePaths.${cfg.layout};
  in pkgs.writeScript "${name}-setup.sh" ''
    #!/usr/bin/env bash
    set -euo pipefail

    readonly SERVER_ID="__SERVER_ID__"
    readonly SYNCTHING_CONFIG="''${SYNCTHING_CONFIG:-$HOME/.config/syncthing}"

    err() { echo "$*" >&2; }
    die() { err "$*"; exit 1; }

    usage() {
      echo "Usage: $0 <base-path> [--apply]"
      echo ""
      echo "Sets up Syncthing to sync emulation folders with bilbo."
      echo ""
      echo "Arguments:"
      echo "  base-path  Root of your emulation setup, e.g. ~/Emulation"
      echo "  --apply    Apply changes (dry run without this flag)"
      echo ""
      echo "Folders to be synced under base-path:"
      echo "  ${device.roms}/"
      echo "  ${device.saves}/"
      echo "  ${device.bios}/"
      exit 1
    }

    [[ $# -ge 1 && "''${1:-}" != "-h" && "''${1:-}" != "--help" ]] || usage

    readonly BASE_PATH="''${1%/}"
    shift

    [[ -d "$BASE_PATH" ]] || die "Base path does not exist: $BASE_PATH"

    command -v syncthing >/dev/null || die "syncthing not found - install it first"
    command -v xmlstarlet >/dev/null || die "xmlstarlet not found - install it (e.g., 'sudo pacman -S xmlstarlet' or 'sudo apt install xmlstarlet')"

    if [[ ! -f "$SYNCTHING_CONFIG/config.xml" ]]; then
      echo "No Syncthing config found. Generating keys..."
      syncthing generate --config="$SYNCTHING_CONFIG"
    fi

    readonly LOCAL_ID=$(syncthing --device-id --config="$SYNCTHING_CONFIG" 2>/dev/null)
    [[ -n "$LOCAL_ID" ]] || die "Failed to get device ID"

    echo "Server ID: $SERVER_ID"
    echo "Local ID:  $LOCAL_ID"
    echo ""
    echo "Add this device to bilbo's Syncthing web UI, then share these folders:"
    echo "  - ${name}-roms"
    echo "  - ${name}-saves"
    echo "  - ${name}-bios"
    echo ""
    echo "Folders to sync under: $BASE_PATH"
    echo "  $BASE_PATH/${device.roms}"
    echo "  $BASE_PATH/${device.saves}"
    echo "  $BASE_PATH/${device.bios}"
    echo ""

    readonly CONFIG="$SYNCTHING_CONFIG/config.xml"
    readonly WANTED_FOLDERS="${name}-roms ${name}-saves ${name}-bios"
    readonly EXISTING=$(xmlstarlet sel -t -m "/configuration/folder[starts-with(@id,'${name}-')]" -v "@id" -o " " "$CONFIG" 2>/dev/null || true)

    echo "Wanted folders: $WANTED_FOLDERS"
    echo "Existing folders: ''${EXISTING:-none}"
    echo ""

    if [[ "''${1:-}" != "--apply" ]]; then
      echo "Run with --apply to configure local folders."
      echo "(Removes old ${name}-* folders from config and adds current ones. Files on disk are not deleted.)"
      exit 0
    fi

    echo "Stopping Syncthing..."
    systemctl --user stop syncthing.service 2>/dev/null || pkill syncthing 2>/dev/null || true
    sleep 1

    cp "$CONFIG" "$CONFIG.bak"
    trap 'err "Error occurred, restoring backup..."; cp "$CONFIG.bak" "$CONFIG"' ERR INT TERM

    if ! xmlstarlet sel -t -v "/configuration/device[@id='$SERVER_ID']/@id" "$CONFIG" &>/dev/null; then
      echo "Adding server device..."
      xmlstarlet ed -L \
        -s "/configuration" -t elem -n "deviceNEW" -v "" \
        -i "//deviceNEW" -t attr -n "id" -v "$SERVER_ID" \
        -i "//deviceNEW" -t attr -n "name" -v "bilbo" \
        -i "//deviceNEW" -t attr -n "compression" -v "metadata" \
        -s "//deviceNEW" -t elem -n "address" -v "dynamic" \
        -r "//deviceNEW" -v "device" \
        "$CONFIG"
    fi

    echo "Removing old ${name}-* folders from config..."
    xmlstarlet ed -L -d "/configuration/folder[starts-with(@id,'${name}-')]" "$CONFIG"

    add_folder() {
      local id="$1" path="$2" type="$3"
      echo "Adding folder $id -> $path ($type)"
      mkdir -p "$path"
      xmlstarlet ed -L \
        -s "/configuration" -t elem -n "folderNEW" -v "" \
        -i "//folderNEW" -t attr -n "id" -v "$id" \
        -i "//folderNEW" -t attr -n "path" -v "$path" \
        -i "//folderNEW" -t attr -n "type" -v "$type" \
        -i "//folderNEW" -t attr -n "rescanIntervalS" -v "3600" \
        -i "//folderNEW" -t attr -n "fsWatcherEnabled" -v "true" \
        -s "//folderNEW" -t elem -n "device" -v "" \
        -i "//folderNEW/device[not(@id)]" -t attr -n "id" -v "$SERVER_ID" \
        -s "//folderNEW" -t elem -n "device" -v "" \
        -i "//folderNEW/device[not(@id)]" -t attr -n "id" -v "$LOCAL_ID" \
        -r "//folderNEW" -v "folder" \
        "$CONFIG"
    }

    add_folder "${name}-roms" "$BASE_PATH/${device.roms}" "receiveonly"
    add_folder "${name}-saves" "$BASE_PATH/${device.saves}" "sendreceive"
    add_folder "${name}-bios" "$BASE_PATH/${device.bios}" "receiveonly"

    echo "Starting Syncthing..."
    systemctl --user start syncthing.service 2>/dev/null || syncthing serve --config="$SYNCTHING_CONFIG" &

    echo "Done! (Backup at $CONFIG.bak)"
  '';

  configGeneratorScript = pkgs.writeShellScript "generate-emulation-configs" ''
    set -euo pipefail

    readonly CONFIG_DIR="${config.users.users.fausto.home}/.config/syncthing"
    readonly OUTPUT_DIR="${base}/_config"

    if [[ ! -f "$CONFIG_DIR/config.xml" ]]; then
      echo >&2 "Syncthing config not found at $CONFIG_DIR/config.xml"
      exit 1
    fi

    readonly SERVER_ID=$(${pkgs.xmlstarlet}/bin/xmlstarlet sel -t -v "/configuration/device[1]/@id" "$CONFIG_DIR/config.xml")
    [[ -n "$SERVER_ID" ]] || { echo >&2 "Failed to extract server device ID"; exit 1; }

    mkdir -p "$OUTPUT_DIR"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg: ''
      ${pkgs.gnused}/bin/sed "s/__SERVER_ID__/$SERVER_ID/g" ${mkSetupScript name cfg} > "$OUTPUT_DIR/${name}-setup.sh"
      chmod +x "$OUTPUT_DIR/${name}-setup.sh"
    '') targets)}

    chown -R ${user}:${group} "$OUTPUT_DIR"
  '';
in {
  systemd.tmpfiles.rules =
    [
      (dir base)
      (dir "${base}/roms")
      (dir "${base}/bios")
      (dir "${base}/saves")
      (dir "${base}/state")
      (dir "${base}/_targets")
    ]
    ++ [(dir "${base}/_config")]
    ++ map (s: dir "${base}/roms/${s}") systems
    ++ map (s: dir "${base}/bios/${s}") baseBiosSystems
    ++ map (s: dir "${base}/saves/${s}") baseSaveDirs
    ++ lib.concatLists (lib.mapAttrsToList mkTargetDirs targets);

  fileSystems = lib.listToAttrs (
    lib.concatLists (lib.mapAttrsToList mkTargetMounts targets)
  );

  services.syncthing = {
    enable = true;
    inherit user group;
    openDefaultPorts = true;
    configDir = "${config.users.users.fausto.home}/.config/syncthing";
    dataDir = base;
    settings = {
      options = {
        urAccepted = -1;
        localAnnounceEnabled = true;
        relaysEnabled = true;
      };
      folders =
        lib.mapAttrs' (name: _cfg: {
          name = "${name}-roms";
          value = {
            path = "${base}/_targets/${name}/roms";
            label = "${name} ROMs";
            type = "sendonly";
          };
        })
        targets
        // lib.mapAttrs' (name: _cfg: {
          name = "${name}-saves";
          value = {
            path = "${base}/_targets/${name}/saves";
            label = "${name} saves";
            type = "sendreceive";
          };
        })
        targets
        // lib.mapAttrs' (name: _cfg: {
          name = "${name}-bios";
          value = {
            path = "${base}/_targets/${name}/bios";
            label = "${name} BIOS";
            type = "sendonly";
          };
        })
        targets;
    };
  };

  systemd.services.emulation-config-generator = {
    description = "Generate Syncthing configs for emulation targets";
    after = ["syncthing.service"];
    wants = ["syncthing.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = configGeneratorScript;
      RemainAfterExit = true;
    };
  };
}
