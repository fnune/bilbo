{pkgs, ...}: {
  services.calibre-web = {
    enable = true;
    package = pkgs.unstable.calibre-web.overridePythonAttrs (prev: {
      dependencies = prev.dependencies ++ prev.optional-dependencies.kobo;
    });
    user = "fausto";
    group = "users";
    listen.ip = "127.0.0.1";
    listen.port = 8083;
    options = {
      calibreLibrary = "/mnt/downloads-1t/Books";
      enableBookConversion = true;
      enableBookUploading = true;
    };
  };
}
