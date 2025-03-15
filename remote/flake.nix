{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {nixpkgs, ...}: let
    forAllSystems = function: nixpkgs.lib.genAttrs ["x86_64-linux"] (system: function (import nixpkgs {inherit system;}));
  in {
    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          awscli2
          biome
          nodejs
          pulumi
          pulumiPackages.pulumi-language-nodejs
          rclone
          yarn
        ];
      };
    });
  };
}
