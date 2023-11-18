{
  description = "fnune's Bilbo—A media server";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/release-23.05";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    bilbo = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./nixos/configuration.nix
        ./nixos/hardware-configuration.nix
        ./nixos/hardware-acceleration.nix
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
