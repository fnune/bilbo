{...}: {
  services.jellyfin = {
    enable = true;
    user = "fausto";
    group = "users";
    openFirewall = true;
  };
}
