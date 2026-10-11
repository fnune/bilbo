{
  lib,
  mounts,
  ...
}: let
  stagedOn = mount: name: {
    inherit name;
    destDir = "${mount}/.nzbget/dst/${name}";
  };

  categories = [
    (stagedOn mounts.downloads-1t "Movies")
    (stagedOn mounts.downloads-2t "Series")
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
in {
  services.nzbget = {
    enable = true;
    group = "users";
    settings = lib.mergeAttrsList (lib.imap1 categorySettings categories);
  };
}
