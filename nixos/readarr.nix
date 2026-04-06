{...}: {
  services.readarr = {
    enable = true;
    user = "fausto";
    group = "users";
    settings.server.urlbase = "/readarr";
  };
}
