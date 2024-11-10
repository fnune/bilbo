{...}: {
  services.readarr = {
    enable = true;
    user = "fausto";
    group = "users";
    openFirewall = true;
  };
}
