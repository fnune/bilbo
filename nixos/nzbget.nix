{
  config,
  lib,
  mounts,
  ...
}: let
  stagedOn = mount: name: {
    inherit name;
    destDir = "${mount}/.nzbget/dst/${name}";
  };

  staged = [
    (stagedOn mounts.downloads-1t "Movies")
    (stagedOn mounts.downloads-2t "Series")
  ];

  categories =
    staged
    ++ [
      {
        name = "Music";
        destDir = "";
      }
      {
        name = "Software";
        destDir = "";
      }
      {
        name = "Books";
        destDir = "${mounts.downloads-1t}/Books";
      }
    ];

  categorySettings = index: category: {
    "Category${toString index}.Name" = category.name;
    "Category${toString index}.DestDir" = category.destDir;
  };

  ownedByNzbget = category: {
    name = category.destDir;
    value.d = {
      inherit (config.services.nzbget) user group;
      mode = "0775";
    };
  };
in {
  services.nzbget = {
    enable = true;
    group = "users";
    settings = lib.mergeAttrsList (lib.imap1 categorySettings categories);
  };

  systemd.tmpfiles.settings."10-nzbget" = lib.listToAttrs (map ownedByNzbget staged);
}
