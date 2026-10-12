{
  config,
  lib,
  libraries,
  mounts,
  pkgs,
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
        name = "Books";
        destDir = libraries.books;
      }
    ];

  categorySettings = index: category: {
    "Category${toString index}.Name" = category.name;
    "Category${toString index}.DestDir" = category.destDir;
  };

  # Passed as command-line options these would show in `ps`, so they're written into the config file instead.
  secretOptions = {
    "Server1.Username" = "eweka-username";
    "Server1.Password" = "eweka-password";
    ControlUsername = "nzbget-username";
    ControlPassword = "nzbget-password";
  };
  configFile = "/var/lib/nzbget/nzbget.conf";

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
    settings =
      lib.mergeAttrsList (lib.imap1 categorySettings categories)
      // {
        MainDir = "${mounts.downloads-1t}/.nzbget";
        ControlIP = "127.0.0.1";
        FormAuth = "yes";
        "Server1.Name" = "Eweka";
        "Server1.Host" = "news.eweka.nl";
        "Server1.Connections" = 50;
        DirectUnpack = "yes";
        # MB. NZBGet's docs (in nzbget.conf) say 50 MB is plenty with DirectWrite, which is on.
        ArticleCache = 100;
        # KB per connection, the value NZBGet's docs recommend.
        WriteBuffer = 1024;
      };
  };

  sops.secrets = lib.genAttrs (builtins.attrValues secretOptions) (_: {});

  systemd.services.nzbget = {
    serviceConfig.LoadCredential = map (secret: "${secret}:${config.sops.secrets.${secret}.path}") (builtins.attrValues secretOptions);
    preStart = lib.mkAfter ''
      rewrite_config() {
        ${lib.getExe pkgs.gawk} "$@" ${configFile} >${configFile}.new
        cat ${configFile}.new >${configFile}
        rm ${configFile}.new
      }

      set_option() {
        OPTION=$1 VALUE=$(cat "$CREDENTIALS_DIRECTORY/$2") rewrite_config \
          'index($0, ENVIRON["OPTION"] "=") == 1 { print ENVIRON["OPTION"] "=" ENVIRON["VALUE"]; next } { print }'
      }

      ${lib.concatStrings (lib.mapAttrsToList (option: secret: "set_option ${option} ${secret}\n") secretOptions)}
      rewrite_config -v last=${toString (builtins.length categories)} \
        'match($0, /^Category([0-9]+)\./, slot) && slot[1] + 0 > last { next } { print }'
    '';
  };

  systemd.tmpfiles.settings."10-nzbget" = lib.listToAttrs (map ownedByNzbget staged);
}
