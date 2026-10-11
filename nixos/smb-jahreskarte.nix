{
  lib,
  pkgs,
  ...
}: let
  port = 8799;
  user = "smb-jahreskarte";
  deployer = "fausto";

  appDir = "/srv/smb-jahreskarte";
  legacyAppDir = "/home/fausto/smb-jahreskarte";

  migrate = import ./migrate-state.nix pkgs;
in {
  users.users.${user} = {
    isSystemUser = true;
    group = user;
  };
  users.groups.${user} = {};

  systemd.tmpfiles.settings."10-smb-jahreskarte".${appDir}.d = {
    user = deployer;
    group = user;
    mode = "0770";
  };

  systemd.services.smb-jahreskarte = {
    description = "SMB Jahreskarte museum map";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      User = user;
      Group = user;
      WorkingDirectory = "-${appDir}";
      ExecStartPre = [
        (migrate {
          from = legacyAppDir;
          to = appDir;
          owner = deployer;
          group = user;
        })
        "+${pkgs.coreutils}/bin/chmod -R g+w ${appDir}" # serve.py writes state.json next to itself
      ];
      ExecStart = "${lib.getExe pkgs.python3} ${appDir}/serve.py";
      Environment = ["SMB_PORT=${toString port}"];
      Restart = "on-failure";
      RestartSec = 3;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [appDir];
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
