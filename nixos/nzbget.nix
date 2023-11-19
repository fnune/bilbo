{config, ...}: {
  services.nzbget = {
    enable = true;
    user = "fausto";
    group = "users";
    settings = {
      MainDir = "${config.users.users.fausto.home}/nzbget";
    };
  };
}
