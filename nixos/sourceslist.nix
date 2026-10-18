{
  config,
  lib,
  pkgs,
  ...
}: let
  package = pkgs.sourceslist;
  postgres = pkgs.postgresql_18;

  database = "sourceslist";
  dbUser = "sourceslist-db";
  dbPort = 5433;
  dbDir = "/var/lib/${dbUser}/${postgres.psqlSchema}";
  dbSocketDir = "/run/${dbUser}";
  databaseUrl = role: password: "postgres://${role}:${password}@127.0.0.1:${toString dbPort}/${database}?sslmode=disable";

  ingestUser = "sourceslist-ingest";
  ingestCacheDir = "/var/cache/${ingestUser}";

  webStatementTimeout = "2s";
  webConnectionLimit = 20;

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
    RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
    RestrictNamespaces = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };

  setUpDatabase = pkgs.writeText "sourceslist-db-setup.sql" ''
    \set ON_ERROR_STOP on
    SELECT 'CREATE ROLE ingest LOGIN CREATEDB' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ingest') \gexec
    SELECT 'CREATE ROLE web LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'web') \gexec
    ALTER ROLE ingest PASSWORD :'ingest_password';
    ALTER ROLE web PASSWORD :'web_password' CONNECTION LIMIT ${toString webConnectionLimit};
    ALTER ROLE web SET default_transaction_read_only = on;
    ALTER ROLE web SET statement_timeout = '${webStatementTimeout}';
    SELECT 'CREATE DATABASE ${database} OWNER ingest' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${database}') \gexec
    \connect ${database}
    -- Untrusted extension: only a superuser can create it.
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
    CREATE EXTENSION IF NOT EXISTS postgres_fdw;
    GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO ingest;
    GRANT USAGE ON SCHEMA public TO web;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO web;
    -- Ingest publishes by renaming new tables, so grants must apply to future ones.
    ALTER DEFAULT PRIVILEGES FOR ROLE ingest IN SCHEMA public GRANT SELECT ON TABLES TO web;
  '';
in {
  sops = {
    secrets = lib.genAttrs ["sourceslist-ingest-db-password" "sourceslist-web-db-password"] (_: {});
    templates = {
      "sourceslist-ingest.env".content = "DATABASE_URL=${databaseUrl "ingest" config.sops.placeholder.sourceslist-ingest-db-password}";
      "sourceslist-web.env".content = "DATABASE_URL=${databaseUrl "web" config.sops.placeholder.sourceslist-web-db-password}";
    };
  };

  bilbo.apps.sourceslist = {
    description = "sourcesli.st - browse Debian packages, bugs and images";
    exposure = "public";
    hostname = "sourcesli.st";
    port = 8091;
    command = lib.getExe' package "web";
    environment.LISTEN_ADDRESS = "127.0.0.1:${toString config.bilbo.apps.sourceslist.port}";
    serviceConfig.EnvironmentFile = config.sops.templates."sourceslist-web.env".path;
    rateLimit = {
      paths = ["/search" "/complete"];
      perMinute = 120;
    };
  };

  users = {
    users.${dbUser} = {
      isSystemUser = true;
      group = dbUser;
    };
    groups.${dbUser} = {};
    users.${ingestUser} = {
      isSystemUser = true;
      group = ingestUser;
    };
    groups.${ingestUser} = {};
  };

  systemd.services = {
    # Not the shared Postgres: that one is Immich's, on a version too old for the UDD dump.
    ${dbUser} = {
      description = "Postgres for sourcesli.st";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      preStart = ''
        if [ ! -e ${dbDir}/PG_VERSION ]; then
          ${postgres}/bin/initdb --pgdata ${dbDir} --username ${dbUser} \
            --auth-local peer --auth-host scram-sha-256 --encoding UTF8 --locale C.UTF-8
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
            "${postgres}/bin/postgres --pgdata ${dbDir}"
            "-c listen_addresses=127.0.0.1"
            "-c port=${toString dbPort}"
            "-c unix_socket_directories=${dbSocketDir}"
            "-c max_connections=40"
            "-c shared_buffers=256MB"
          ];
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          KillMode = "mixed";
          KillSignal = "SIGINT";
          TimeoutSec = 120;
          MemoryMax = "2G";
        };
    };

    sourceslist-db-setup = {
      description = "Create sourcesli.st's database and roles";
      after = ["${dbUser}.service"];
      requires = ["${dbUser}.service"];
      serviceConfig =
        hardening
        // {
          Type = "oneshot";
          RemainAfterExit = true;
          User = dbUser;
          Group = dbUser;
          LoadCredential = [
            "ingest:${config.sops.secrets.sourceslist-ingest-db-password.path}"
            "web:${config.sops.secrets.sourceslist-web-db-password.path}"
          ];
        };
      script = ''
        ${postgres}/bin/psql --host ${dbSocketDir} --port ${toString dbPort} --dbname postgres --no-psqlrc \
          --set ingest_password="$(cat "$CREDENTIALS_DIRECTORY/ingest")" \
          --set web_password="$(cat "$CREDENTIALS_DIRECTORY/web")" \
          --file ${setUpDatabase}
      '';
    };

    sourceslist-migrate = {
      description = "Bring sourcesli.st's schema up to date";
      after = ["sourceslist-db-setup.service"];
      requires = ["sourceslist-db-setup.service"];
      serviceConfig =
        hardening
        // {
          Type = "oneshot";
          RemainAfterExit = true;
          User = ingestUser;
          Group = ingestUser;
          EnvironmentFile = config.sops.templates."sourceslist-ingest.env".path;
          ExecStart = lib.getExe' package "migrate";
        };
    };

    sourceslist = {
      after = ["sourceslist-migrate.service"];
      requires = ["sourceslist-migrate.service"];
    };

    # Upstream publishes every two days; the download is conditional, so daily is free.
    sourceslist-ingest = {
      description = "Copy the Ultimate Debian Database into sourcesli.st";
      after = ["sourceslist-migrate.service" "network-online.target"];
      requires = ["sourceslist-migrate.service"];
      wants = ["network-online.target"];
      startAt = "04:30";
      path = [postgres];
      environment = {
        UDD_DUMP_URL = "https://udd.debian.org/dumps/udd.dump";
        UDD_CACHE_DIR = ingestCacheDir;
        UDD_SCRATCH_DATABASE = "udd_scratch";
      };
      serviceConfig =
        hardening
        // {
          Type = "oneshot";
          User = ingestUser;
          Group = ingestUser;
          CacheDirectory = ingestUser;
          EnvironmentFile = config.sops.templates."sourceslist-ingest.env".path;
          ExecStart = lib.getExe' package "ingest";
          Nice = 10;
          IOSchedulingClass = "idle";
          MemoryMax = "2G";
        };
    };
  };

  systemd.timers.sourceslist-ingest.timerConfig.Persistent = true;
}
