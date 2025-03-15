{
  description = "fnune's Bilbo—A media server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko/v1.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    disko,
    ...
  }: let
    system = "x86_64-linux";

    unstableOverlay = final: prev: {
      unstable = nixpkgs-unstable.legacyPackages.${system};
    };

    bilbo = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {nixpkgs.overlays = [unstableOverlay];}
        ./nixos/configuration.nix
        ./nixos/drives.nix
        ./nixos/hardware-configuration.nix
        ./nixos/hardware-acceleration.nix
        ./nixos/network-configuration.nix
        disko.nixosModules.disko
      ];
    };
    bilboVirtual = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {nixpkgs.overlays = [unstableOverlay];}
        ./nixos/configuration.nix
        ./nixos/development-configuration.nix
      ];
    };
  in {
    nixosConfigurations.bilbo = bilbo;
    nixosConfigurations.bilboVirtual = bilboVirtual;
  };
}
