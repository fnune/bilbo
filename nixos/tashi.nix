{
  config,
  lib,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.tashi;
  package = pkgs.tashi.override {inherit (app) basePath;};
  stateDir = "/var/lib/tashi";

  model = "claude-haiku-5-5";
  keepBackups = 20;

  backupUserData = pkgs.writeShellScript "tashi-backup" ''
    set -euo pipefail
    cd "$STATE_DIRECTORY"
    stamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p "backups/$stamp"
    for f in settings.json history.json timeline.json; do
      [ -f "$f" ] && cp -a "$f" "backups/$stamp/"
    done
    ls -1d backups/[0-9]*/ | sort | head -n -${toString keepBackups} | xargs -r rm -r
  '';

  start = pkgs.writeShellScript "tashi-start" ''
    ANTHROPIC_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/anthropic-api-key")
    export ANTHROPIC_API_KEY
    exec ${lib.getExe package}
  '';
in {
  sops.secrets.anthropic-api-key = {};

  bilbo.apps.tashi = {
    description = "Tashi - T1D insulin dose calculator";
    port = 3210;
    command = "${start}";
    environment = {
      PORT = toString app.port;
      DATA_DIR = stateDir;
      BASE_PATH = app.basePath;
      LLM_MODEL = model;
    };
    credentials.anthropic-api-key = config.sops.secrets.anthropic-api-key.path;
    serviceConfig.ExecStartPre = backupUserData;
  };
}
