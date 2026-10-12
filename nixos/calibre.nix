{pkgs, ...}: {
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

  # UMask stays at the default so books added here remain readable outside the users group.
  systemd.services.calibre-web.serviceConfig.PrivateUsers = true;
}
