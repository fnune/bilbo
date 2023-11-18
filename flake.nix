{
  description = "fnune's Bilbo—A media server";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
  };
  outputs = {
    self,
    nixpkgs,
  }: {
    nixosConfigurations = {
      "bilbo" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./nixos/configuration.nix
          ./nixos/hardware-configuration.nix
          ./nixos/hardware-acceleration.nix
        ];
      };
    };
  };
}
