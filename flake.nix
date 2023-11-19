{
  description = "fnune's Bilbo—A media server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        darwin.follows = "";
      };
    };
  };

  outputs = {
    nixpkgs,
    disko,
    agenix,
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
        agenix.nixosModules.default
        {
          environment.systemPackages = [agenix.packages.${system}.default];
        }
        disko.nixosModules.disko
      ];
    };
    bilboVirtual = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./nixos/configuration.nix
        ./nixos/development-configuration.nix
        agenix.nixosModules.default
        {
          environment.systemPackages = [agenix.packages.${system}.default];
        }
      ];
    };
  in {
    nixosConfigurations.bilbo = bilbo;
    nixosConfigurations.bilboVirtual = bilboVirtual;
  };
}
