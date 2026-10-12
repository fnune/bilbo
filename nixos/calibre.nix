{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.calibre-web;
  appDb = "/var/lib/${cfg.dataDir}/app.db";

  # The Kobo sync on calibre.fnune.com needs these; the module has no options for them.
  settings = {
    config_kobo_sync = 1;
    config_kobo_proxy = 1;
    # Kobo sync links are built from this; Caddy serves on 443.
    config_external_port = 443;
  };
  applySettings = pkgs.writeShellScript "calibre-web-apply-settings" ''
    # On a fresh install the database doesn't exist yet; the next start applies these.
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
      calibreLibrary = "/mnt/downloads-1t/Books";
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
    # UMask stays at the default so books added here remain readable outside the users group.
    serviceConfig.PrivateUsers = true;
  };
}
