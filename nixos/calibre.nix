{
  config,
  lib,
  libraries,
  pkgs,
  ...
}: let
  cfg = config.services.calibre-web;
  appDb = "/var/lib/${cfg.dataDir}/app.db";

  settings = {
    config_kobo_sync = 1;
    config_kobo_proxy = 1;
    config_external_port = 443;
  };
  applySettings = pkgs.writeShellScript "calibre-web-apply-settings" ''
    [ -f ${libraries.books}/metadata.db ] || HOME=$(mktemp -d) ${cfg.calibrePackage}/bin/calibredb --library-path ${libraries.books} list
    [ -f ${appDb} ] || exit 0
    ${lib.getExe pkgs.sqlite} ${appDb} "update settings set ${
      lib.concatStringsSep ", " (lib.mapAttrsToList (k: v: "${k} = ${toString v}") settings)
    }"
  '';
in {
  services.calibre-web = {
    enable = true;
    package = pkgs.calibre-web.overridePythonAttrs (prev: {
      dependencies = prev.dependencies ++ prev.optional-dependencies.kobo;
    });
    group = "users";
    listen.ip = "127.0.0.1";
    listen.port = 8083;
    options = {
      calibreLibrary = libraries.books;
      enableBookConversion = true;
      enableBookUploading = true;
      enableKepubify = true;
    };
  };

  systemd.services.calibre-web-settings = {
    description = "Apply Calibre-web's settings from this repository";
    before = ["calibre-web.service"];
    requiredBy = ["calibre-web.service"];
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
      Group = cfg.group;
      ExecStart = applySettings;
    };
  };

  systemd.services.calibre-web = {
    restartTriggers = [applySettings];
    serviceConfig = {
      PrivateUsers = true;
      SystemCallFilter = ["setpriority"];
    };
  };

  bilbo.backups.calibre-web.paths = ["/var/lib/${cfg.dataDir}"];
}
