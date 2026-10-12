{pkgs, ...}: {
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 2;
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  nix = {
    settings.experimental-features = ["nix-command" "flakes"];
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 1d";
    };
  };

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
    curl
    fd
    file
    git
    htop
    jq
    neovim
    ripgrep
    tmux
    tree
    unzip
    wget
  ];

  environment.sessionVariables = {
    EDITOR = "nvim";
  };

  # To add my identity:
  # ssh-copy-id -i ~/.ssh/id_ed25519.pub fausto@bilbo-ip
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = ["fausto"];
    };
  };
  networking.firewall = let
    # My own Syncthing (kyaraben-syncthing, a user service) on non-default ports.
    syncthingSync = 22100;
    syncthingLocalDiscovery = 21127;
    ssh = {allowedTCPPorts = [22];};
  in {
    allowedTCPPorts = [syncthingSync];
    allowedUDPPorts = [syncthingSync syncthingLocalDiscovery];
    interfaces = {
      eno1 = ssh;
      wg0 = ssh;
    };
  };

  security.sudo.extraConfig = "Defaults pwfeedback";
  security.sudo.execWheelOnly = true;

  system.stateVersion = "23.05";

  imports = [
    ./arr-settings.nix
    ./backups.nix
    ./bazarr.nix
    ./caddy.nix
    ./calibre.nix
    ./crowdsec.nix
    ./fail2ban.nix
    ./frigate.nix
    ./home-assistant.nix
    ./immich.nix
    ./immich-public-proxy.nix
    ./jellyfin.nix
    ./monitoring.nix
    ./mosquitto.nix
    ./nzbget.nix
    ./papra.nix
    ./pincho.nix
    ./prowlarr.nix
    ./radarr.nix
    ./recyclarr.nix
    ./secrets.nix
    ./seerr.nix
    ./smb-jahreskarte.nix
    ./sonarr.nix
    ./wireguard.nix
    ./zigbee2mqtt.nix
  ];
}
