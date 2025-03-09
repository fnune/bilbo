{
  description = "fnune's Bilbo—A media server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    disko = {
      url = "github:nix-community/disko/v1.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    ...
  }: let
    system = "x86_64-linux";
    bilbo = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
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
        ./nixos/configuration.nix
        ./nixos/development-configuration.nix
      ];
    };
  in {
    nixosConfigurations.bilbo = bilbo;
    nixosConfigurations.bilboVirtual = bilboVirtual;
  };
}
