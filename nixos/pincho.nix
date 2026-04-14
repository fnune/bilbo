{pkgs, ...}: let
  port = "3210";
  dataDir = "/var/lib/pincho";
  appDir = "/opt/pincho";
in {
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 pincho users -"
    "d ${appDir} 0755 pincho users -"
  ];

  users.users.pincho = {
    isSystemUser = true;
    group = "users";
    home = dataDir;
    createHome = true;
  };

  systemd.services.pincho = {
    description = "Pincho - T1D insulin dose calculator";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.nodejs_22}/bin/node ${appDir}/packages/backend/dist/server.js";
      Restart = "always";
      User = "pincho";
      Group = "users";
      WorkingDirectory = "${appDir}/packages/backend";
      EnvironmentFile = "${dataDir}/.env";
      Environment = [
        "PORT=${port}"
        "DATA_DIR=${dataDir}"
        "BASE_PATH=/pincho"
      ];
    };
  };
}
