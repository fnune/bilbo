{...}: {
  services.bazarr = {
    enable = true;
    user = "fausto";
    group = "users";
    openFirewall = true;
  };
}
