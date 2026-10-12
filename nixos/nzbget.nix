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
      # NZBGet skips a category with an empty name; nzbget.conf still defines these two slots.
      unused
      unused
      {
        name = "Books";
        destDir = "${mounts.downloads-1t}/Books";
      }
    ];

  unused = {
    name = "";
    destDir = "";
  };

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
        "Server1.Connections" = 50;
        # Unpacks while downloading, so imports start sooner.
        DirectUnpack = "yes";
        # MB. With DirectWrite on (nzbget.conf), NZBGet's docs say even 50 MB is effective.
        ArticleCache = 100;
        # KB per connection; the value NZBGet's docs recommend.
        WriteBuffer = 1024;
      };
  };

  systemd.tmpfiles.settings."10-nzbget" = lib.listToAttrs (map ownedByNzbget staged);
}
