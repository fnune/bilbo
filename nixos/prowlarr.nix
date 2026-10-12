{...}: {
  services.prowlarr = {
    enable = true;
    settings.server = {
      urlbase = "/prowlarr";
      bindaddress = "127.0.0.1";
    };
  };
}
