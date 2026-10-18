{
  config,
  pkgs,
  ...
}: {
  bilbo.apps.lists = {
    description = "Books, games and cooking notes";
    site = import ./site.nix {
      inherit pkgs;
      vault = pkgs.listsVault;
      inherit (config.bilbo.apps.lists) basePath;
    };
  };
}
