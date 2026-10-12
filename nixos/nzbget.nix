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
    # Logins stay in nzbget.conf: these become command-line arguments, visible in `ps`.
    settings =
      lib.mergeAttrsList (lib.imap1 categorySettings categories)
      // {
        MainDir = "${mounts.downloads-1t}/.nzbget";
        ControlIP = "127.0.0.1";
        FormAuth = "yes";
        "Server1.Name" = "Eweka";
        "Server1.Host" = "news.eweka.nl";
        "Server1.Port" = 563;
        "Server1.Encryption" = "yes";
        "Server1.CertVerification" = "Strict";
        "Server1.Connections" = 50;
      };
  };

  systemd.tmpfiles.settings."10-nzbget" = lib.listToAttrs (map ownedByNzbget staged);
}
