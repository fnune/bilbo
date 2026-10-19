{
  description = "fnune's Bilbo—A media server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko/v1.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sourceslist.url = "github:fnune/sourcesli.st";
    family-history.url = "github:fnune/family-history";
    family-history-fausto = {
      url = "github:fnune/family-history-fausto";
      flake = false;
    };
    fire.url = "github:fnune/fire";
    lists = {
      url = "github:fnune/lists";
      flake = false;
    };
    shmups.url = "github:fnune/shmups";
    smb.url = "github:fnune/smb";
    tashi.url = "github:fnune/tashi";
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    disko,
    sops-nix,
    family-history,
    family-history-fausto,
    fire,
    lists,
    shmups,
    smb,
    sourceslist,
    tashi,
    ...
  }: let
    system = "x86_64-linux";

    unstableOverlay = final: prev: {
      unstable = nixpkgs-unstable.legacyPackages.${system};
    };

    appsOverlay = final: prev: {
      familyData = family-history-fausto;
      familyMap = family-history.packages.${system}.default.override {family = family-history-fausto;};
      fire = fire.packages.${system}.default;
      fireSource = fire;
      listsVault = lists;
      shmups = shmups.packages.${system}.default;
      smb = smb.packages.${system}.default;
      sourceslist = sourceslist.packages.${system}.default;
      tashi = tashi.packages.${system}.default;
    };

    bilbo = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {nixpkgs.overlays = [unstableOverlay appsOverlay];}
        ./nixos/configuration.nix
        ./nixos/drives.nix
        ./nixos/hardware-configuration.nix
        ./nixos/hardware-acceleration.nix
        ./nixos/network-configuration.nix
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
      ];
    };
  in {
    nixosConfigurations.bilbo = bilbo;
  };
}
