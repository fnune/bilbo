{
  config,
  lib,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.tashi;
  backupDir = "/var/lib/tashi/backups";
  databasePath = "/var/lib/tashi/tashi.sqlite";
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

  # The live file can change while borg reads it; these copies cannot.
  backupDatabase = pkgs.writeShellScript "tashi-backup" ''
    set -euo pipefail
    [ -f ${databasePath} ] || exit 0
    stamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p ${backupDir}
    ${pkgs.sqlite}/bin/sqlite3 ${databasePath} ".backup '${backupDir}/$stamp.sqlite'"
    ls -1 ${backupDir}/*.sqlite | sort | head -n -${toString keepBackups} | xargs -r rm
  '';

in {
  bilbo.apps.tashi = {
    description = "Tashi - T1D insulin dose calculator";
    backup = true;
    port = 3210;
    command = "${lib.getExe pkgs.tashi} --database ${databasePath} --port ${toString app.port} --base-path ${app.basePath}";
    serviceConfig.ExecStartPre = backupDatabase;
  };

  systemd = {
    services = {
      # Before the midnight borg run, so the copy is in that night's archive.
      tashi-backup = {
        description = "Copy Tashi's database";
        startAt = "23:30";
        serviceConfig =
          hardening
          // {
            Type = "oneshot";
            User = "tashi";
            Group = "tashi";
            StateDirectory = "tashi";
            StateDirectoryMode = "0700";
            ExecStart = backupDatabase;
          };
      };
    };

    timers.tashi-backup.timerConfig.Persistent = true;
  };
}
