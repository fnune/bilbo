{...}: {
  users.users.vmfausto = {
    isNormalUser = true;
    description = "Virtual Fausto Núñez Alberro";
    extraGroups = ["networkmanager" "wheel"];
    packages = [];
    initialPassword = "vmfausto";
  };
}
