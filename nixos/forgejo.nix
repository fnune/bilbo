{
  config,
  lib,
  pkgs,
  ...
}: let
  hostname = "git.fnune.com";
  socket = "/run/forgejo/forgejo.sock";

  storage = "/mnt/mirrored/forgejo";
  stateDir = "${storage}/state";
  directoriesTmpfilesRefusesUnderFaustosMount = [stateDir] ++ map (dir: "${stateDir}/${dir}") ["conf" "custom" "custom/conf" "data" "dump" "log" "repositories"];

  admin = {
    username = "fnune";
    email = "fausto.nunez@mailbox.org";
  };

  cfg = config.services.forgejo;
  forgejo = lib.getExe cfg.package;
in {
  sops.secrets.forgejo-admin-password = {};

  users = {
    users.git = {
      isSystemUser = true;
      group = "git";
      home = stateDir;
      useDefaultShell = true;
    };
    groups.git = {};
  };

  services.openssh.settings.AllowUsers = ["git"];

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo-lts;
    user = "git";
    group = "git";
    inherit stateDir;
    database.type = "sqlite3";
    settings = {
      server = {
        DOMAIN = hostname;
        ROOT_URL = "https://${hostname}/";
        PROTOCOL = "http+unix";
        HTTP_ADDR = socket;
        SSH_DOMAIN = hostname;
        OFFLINE_MODE = true;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };
      repository.DEFAULT_PRIVATE = "private";
      session.COOKIE_SECURE = true;
      mirror = {
        DEFAULT_INTERVAL = "1h";
        MIN_INTERVAL = "10m";
      };
      actions.ENABLED = false;
      log.LEVEL = "Warn";
    };
  };

  systemd.services = {
    forgejo-secrets = {
      unitConfig.RequiresMountsFor = [storage];
      serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o ${cfg.user} -g ${cfg.group} -m 0750 ${lib.escapeShellArgs directoriesTmpfilesRefusesUnderFaustosMount}";
    };
    forgejo = {
      unitConfig.RequiresMountsFor = [storage];
      serviceConfig.CPUWeight = 20;
    };

    forgejo-admin = {
      description = "Create Forgejo's admin account";
      after = ["forgejo.service"];
      requires = ["forgejo.service"];
      wantedBy = ["multi-user.target"];
      environment = {inherit (config.systemd.services.forgejo.environment) USER HOME FORGEJO_WORK_DIR FORGEJO_CUSTOM;};
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        LoadCredential = ["password:${config.sops.secrets.forgejo-admin-password.path}"];
      };
      script = ''
        if ${forgejo} admin user list --admin | ${pkgs.gawk}/bin/awk '{print $2}' | grep --quiet --line-regexp ${admin.username}; then
          exit 0
        fi
        ${forgejo} admin user create --admin \
          --username ${admin.username} \
          --email ${admin.email} \
          --password "$(cat "$CREDENTIALS_DIRECTORY/password")" \
          --must-change-password=false
      '';
    };
  };

  systemd.tmpfiles.rules = ["d ${storage} 0750 git git -"];

  bilbo.backups.forgejo.stopToCopy = {
    service = "forgejo";
    directory = stateDir;
  };

  _module.args.forgejo = {
    inherit hostname socket;
    inherit (admin) username;
    repositories = cfg.repositoryRoot;
    database = cfg.database.path;
  };
}
