{pkgs, config, ...}: let
  port = "3210";
  homeDir = config.users.users.fausto.home;
  appDir = "${homeDir}/pincho";
  dataDir = "${appDir}/data";
in {
  systemd.services.pincho = {
    description = "Pincho - T1D insulin dose calculator";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.nodejs_22}/bin/node ${appDir}/packages/backend/dist/server.js";
      Restart = "always";
      User = "fausto";
      Group = "users";
      WorkingDirectory = "${appDir}/packages/backend";
      EnvironmentFile = "${appDir}/.env";
      Environment = [
        "PORT=${port}"
        "DATA_DIR=${dataDir}"
        "BASE_PATH=/pincho"
      ];
    };
  };
}
