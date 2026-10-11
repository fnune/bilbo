{...}: {
  services.radarr = {
    enable = true;
    group = "users";
    settings.server.urlbase = "/radarr";
  };
}
