{
  config,
  lib,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.fire;
  source = pkgs.fireSource;
  privateFiles = ["profile" "portfolio" "income"];
  examples = ["assumptions" "expenses"] ++ privateFiles;
  secretName = name: "fire-${name}";

  # Links only: the private files are decrypted outside the store.
  dataDir = pkgs.linkFarm "fire-data" (
    map (name: {
      name = "${name}.toml";
      path = "${source}/data/${name}.toml";
    })
    examples
    ++ map (name: {
      name = "${name}.local.toml";
      path = config.sops.secrets.${secretName name}.path;
    })
    privateFiles
  );
in {
  sops.secrets = lib.listToAttrs (map (name:
    lib.nameValuePair (secretName name) {
      sopsFile = "${source}/data/${name}.local.sops.toml";
      format = "binary";
      owner = "fire";
      restartUnits = ["fire.service"];
    })
  privateFiles);

  bilbo.apps.fire = {
    description = "FIRE projections";
    port = 3211;
    command = lib.getExe pkgs.fire;
    environment = {
      PORT = toString app.port;
      FIRE_BASE_PATH = app.basePath;
      FIRE_DATA_DIR = "${dataDir}";
    };
  };
}
