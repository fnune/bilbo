{...}: {
  services.radarr = {
    enable = true;
    group = "users";
    settings = {
      server = {
        urlbase = "/radarr";
        bindaddress = "127.0.0.1";
      };
      # Caddy reaches it from localhost, so "disabled for local addresses" would mean no login at all.
      auth = {
        method = "Forms";
        required = "Enabled";
      };
    };
  };
}
