{
  config,
  pkgs,
  ...
}: {
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
    extraOptions = "!include ${config.sops.templates."nix-private-github-access.conf".path}";
  };

  sops = {
    secrets.github-read-token = {};
    templates."nix-private-github-access.conf" = {
      content = "access-tokens = github.com=${config.sops.placeholder.github-read-token}";
      group = "wheel";
      mode = "0440";
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
    syncthingSync = 22100;
    syncthingLocalDiscovery = 21127;
    ssh = {allowedTCPPorts = [22];};
    dropSynWithIpOptions = ''-p tcp --syn -m u32 ! --u32 "0>>24&0xF=5" -j DROP''; # https://ubuntu.com/security/CVE-2026-98432
  in {
    extraCommands = "iptables -t raw -I PREROUTING ${dropSynWithIpOptions}";
    extraStopCommands = "iptables -t raw -D PREROUTING ${dropSynWithIpOptions} || true";
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
    ./apps.nix
    ./arr-settings.nix
    ./backups.nix
    ./bazarr.nix
    ./caddy.nix
    ./calibre.nix
    ./crowdsec.nix
    ./fail2ban.nix
    ./family.nix
    ./fire.nix
    ./frigate.nix
    ./home-assistant.nix
    ./immich.nix
    ./immich-public-proxy.nix
    ./jellyfin.nix
    ./lists
    ./monitoring.nix
    ./mosquitto.nix
    ./nzbget.nix
    ./offline-kit.nix
    ./papra.nix
    ./tashi.nix
    ./recyclarr.nix
    ./secrets.nix
    ./seerr.nix
    ./servarr.nix
    ./settings-services.nix
    ./shmups.nix
    ./smb.nix
    ./sourceslist.nix
    ./tools.nix
    ./wireguard.nix
    ./zigbee2mqtt.nix
  ];
}
