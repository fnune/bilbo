{...}: {
  services.sonarr = {
    enable = true;
    group = "users";
    settings.server.urlbase = "/sonarr";
  };
}
