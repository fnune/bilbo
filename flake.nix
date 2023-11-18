{
  description = "fnune's Bilbo—A media server";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/release-23.05";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
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
      modules = [./nixos/configuration.nix];
    };
  in {
    nixosConfigurations.bilbo = bilbo;
    nixosConfigurations.bilboVirtual = bilboVirtual;
  };
}
