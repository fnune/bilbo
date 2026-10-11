{
  config,
  lib,
  pkgs,
  ...
}: let
  port = 3210;
  basePath = "/pincho";
  deployer = "fausto";
  user = "pincho";

  appDir = "/srv/pincho";
  dataDir = "/var/lib/pincho";

  model = "claude-haiku-5-5";
  keepBackups = 20;

  backupUserData = pkgs.writeShellScript "pincho-backup" ''
    set -euo pipefail
    cd "$STATE_DIRECTORY"
    stamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p "backups/$stamp"
    for f in settings.json history.json timeline.json; do
      [ -f "$f" ] && cp -a "$f" "backups/$stamp/"
    done
    ls -1d backups/[0-9]*/ | sort | head -n -${toString keepBackups} | xargs -r rm -r
  '';

  start = pkgs.writeShellScript "pincho-start" ''
    ANTHROPIC_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/anthropic-api-key")
    export ANTHROPIC_API_KEY
    exec ${lib.getExe pkgs.nodejs_22} ${appDir}/packages/backend/dist/server.js
  '';
in {
  sops.secrets.anthropic-api-key = {};

  users.users.${user} = {
    isSystemUser = true;
    group = user;
  };
  users.groups.${user} = {};

  systemd.tmpfiles.settings."10-pincho".${appDir}.d = {
    user = deployer;
    group = user;
    mode = "0750";
  };

  systemd.services.pincho = {
    description = "Pincho - T1D insulin dose calculator";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = user;
      Group = user;
      StateDirectory = user;
      WorkingDirectory = "-${appDir}/packages/backend"; # absent until the first deploy
      ExecStartPre = [backupUserData];
      ExecStart = start;
      LoadCredential = ["anthropic-api-key:${config.sops.secrets.anthropic-api-key.path}"];
      Environment = [
        "PORT=${toString port}"
        "DATA_DIR=${dataDir}"
        "FOODS_DB=${appDir}/data/foods.db"
        "BASE_PATH=${basePath}"
        "LLM_MODEL=${model}"
      ];
      Restart = "always";
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  security.sudo.extraRules = [
    {
      users = [deployer];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart pincho.service";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}
