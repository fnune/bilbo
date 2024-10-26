{pkgs, ...}: {
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;
  nix.settings.experimental-features = ["nix-command" "flakes"];

  networking = {
    hostName = "bilbo";
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  services.xserver.xkb = {
    layout = "es";
    variant = "";
  };

  console.keyMap = "es";

  users.users.fausto = {
    isNormalUser = true;
    description = "Fausto Núñez Alberro";
    extraGroups = ["networkmanager" "wheel"];
    packages = [];
  };

  environment.systemPackages = with pkgs; [
    git
    htop
    neovim
    tmux
  ];

  # To add my identity:
  # ssh-copy-id -i ~/.ssh/id_ed25519.pub fausto@bilbo-ip
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall.allowedTCPPorts = [22];

  system.stateVersion = "23.05";

  imports = [
    ./tailscale.nix
    ./monitoring.nix
    ./jellyfin.nix
    ./nzbget.nix
    ./radarr.nix
    ./sonarr.nix
    ./nextcloud.nix
  ];
}
