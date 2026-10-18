{
  config,
  lib,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.shmups;
in {
  bilbo.apps.shmups = {
    description = "Arcade shmup 1CC guide";
    port = 3220;
    command = lib.getExe pkgs.shmups;
    environment = {
      PORT = toString app.port;
      BASE_PATH = app.basePath;
      DB_PATH = "/var/lib/shmups/shmups.db";
    };
  };
}
