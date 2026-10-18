{
  config,
  lib,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.smb;
in {
  bilbo.apps.smb = {
    description = "Museum map for the SMB annual pass";
    backup = true;
    port = 8799;
    command = lib.getExe pkgs.smb;
    environment = {
      SMB_PORT = toString app.port;
      SMB_BASE_PATH = app.basePath;
      SMB_STATE_FILE = "/var/lib/smb/state.json";
    };
  };
}
