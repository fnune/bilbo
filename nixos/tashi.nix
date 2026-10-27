{
  config,
  lib,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.tashi;
  package = pkgs.tashi.override {inherit (app) basePath;};
  postgres = pkgs.postgresql_18;

  database = "tashi";
  dbUser = "tashi-db";
  dbDir = "/var/lib/${dbUser}/${postgres.psqlSchema}";
  dbSocketDir = "/run/${dbUser}";
  backupDir = "/var/lib/tashi/backups";

  model = "claude-haiku-5-5";
  keepBackups = 20;

  hardening = {
    CapabilityBoundingSet = "";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = ["AF_UNIX"];
    RestrictNamespaces = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };

  setUpDatabase = pkgs.writeText "tashi-db-setup.sql" ''
    \set ON_ERROR_STOP on
    SELECT 'CREATE ROLE tashi LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tashi') \gexec
    SELECT 'CREATE DATABASE ${database} OWNER tashi' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${database}') \gexec
  '';

  dumpDatabase = pkgs.writeShellScript "tashi-backup" ''
    set -euo pipefail
    stamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p ${backupDir}
    ${postgres}/bin/pg_dump --host ${dbSocketDir} --format custom --file ${backupDir}/$stamp.dump ${database}
    ls -1 ${backupDir}/*.dump | sort | head -n -${toString keepBackups} | xargs -r rm
  '';

  start = pkgs.writeShellScript "tashi-start" ''
    ANTHROPIC_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/anthropic-api-key")
    export ANTHROPIC_API_KEY
    exec ${lib.getExe package}
  '';
in {
  sops.secrets.anthropic-api-key = {};

  users = {
    users.${dbUser} = {
      isSystemUser = true;
      group = dbUser;
    };
    groups.${dbUser} = {};
  };

  bilbo.apps.tashi = {
    description = "Tashi - T1D insulin dose calculator";
    backup = true;
    port = 3210;
    command = "${start}";
    environment = {
      PORT = toString app.port;
      DATABASE_URL = "postgres://tashi@localhost/${database}?host=${dbSocketDir}";
      BASE_PATH = app.basePath;
      LLM_MODEL = model;
    };
    credentials.anthropic-api-key = config.sops.secrets.anthropic-api-key.path;
    serviceConfig.ExecStartPre = dumpDatabase;
  };

  systemd = {
    services = {
      # Not the shared Postgres: that one is Immich's and ends support in November 2026.
      ${dbUser} = {
        description = "Postgres for Tashi";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        preStart = ''
          if [ ! -e ${dbDir}/PG_VERSION ]; then
            ${postgres}/bin/initdb --pgdata ${dbDir} --username ${dbUser} \
              --auth-local peer --encoding UTF8 --locale C.UTF-8
          fi
        '';
        serviceConfig =
          hardening
          // {
            Type = "notify";
            User = dbUser;
            Group = dbUser;
            StateDirectory = dbUser;
            StateDirectoryMode = "0700";
            RuntimeDirectory = dbUser;
            ExecStart = lib.concatStringsSep " " [
              "${postgres}/bin/postgres -D ${dbDir}"
              "-c listen_addresses="
              "-c unix_socket_directories=${dbSocketDir}"
              "-c max_connections=20"
              "-c shared_buffers=64MB"
            ];
            ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
            KillMode = "mixed";
            KillSignal = "SIGINT";
            TimeoutSec = 120;
            MemoryMax = "512M";
          };
      };

      tashi-db-setup = {
        description = "Create Tashi's database role and database";
        after = ["${dbUser}.service"];
        requires = ["${dbUser}.service"];
        serviceConfig =
          hardening
          // {
            Type = "oneshot";
            RemainAfterExit = true;
            User = dbUser;
            Group = dbUser;
          };
        script = ''
          ${postgres}/bin/psql --host ${dbSocketDir} --dbname postgres --no-psqlrc --file ${setUpDatabase}
        '';
      };

      tashi = {
        after = ["tashi-db-setup.service"];
        requires = ["tashi-db-setup.service"];
      };

      # Before the midnight borg run, so the dump is in that night's archive.
      tashi-backup = {
        description = "Dump Tashi's database";
        after = ["tashi-db-setup.service"];
        requires = ["tashi-db-setup.service"];
        startAt = "23:30";
        serviceConfig =
          hardening
          // {
            Type = "oneshot";
            User = "tashi";
            Group = "tashi";
            StateDirectory = "tashi";
            StateDirectoryMode = "0700";
            ExecStart = dumpDatabase;
          };
      };
    };

    timers.tashi-backup.timerConfig.Persistent = true;
  };
}
