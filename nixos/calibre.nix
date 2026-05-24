{...}: {
  services.calibre-web = {
    enable = true;
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
