{
  config,
  forgejo,
  lib,
  pkgs,
  ...
}: let
  hostname = "code.fnune.com";

  publicRepos = {};

  forgejoRepository = name: "${forgejo.repositories}/${forgejo.username}/${lib.toLower name}.git";

  assets = pkgs.linkFarm "cgit-assets" (lib.genAttrs ["cgit.css" "cgit.png" "favicon.ico" "robots.txt"] (file: "${pkgs.cgit}/cgit/${file}"));

  filters = "${pkgs.cgit}/lib/cgit/filters";

  globalSettings = ''
    root-title=fnune's code
    root-desc=Public repositories
    virtual-root=/
    css=/cgit.css
    logo=/cgit.png
    favicon=/favicon.ico
    readme=:README.md
    about-filter=${filters}/about-formatting.sh
    source-filter=${filters}/syntax-highlighting.py
  '';
  repoSections = lib.concatStrings (lib.mapAttrsToList (name: repo: ''
      repo.url=${name}
      repo.path=${forgejoRepository name}
      repo.desc=${repo.desc}
    '')
    publicRepos);
  cgitrc = pkgs.writeText "cgitrc" (globalSettings + repoSections);

  everythingOnTheMirroredMount = "/mnt/mirrored";
in {
  users = {
    users.cgit = {
      isSystemUser = true;
      group = "cgit";
    };
    groups.cgit = {};
  };

  services.fcgiwrap.instances.cgit = {
    process = {
      user = "cgit";
      group = "cgit";
    };
    socket = {
      inherit (config.services.caddy) user group;
      mode = "0600";
    };
  };

  systemd.services.fcgiwrap-cgit = {
    unitConfig.RequiresMountsFor = [forgejo.repositories];
    serviceConfig = {
      SupplementaryGroups = [config.services.forgejo.group];
      TemporaryFileSystem = ["${everythingOnTheMirroredMount}:ro"];
      BindReadOnlyPaths = lib.mapAttrsToList (name: _: "-${forgejoRepository name}") publicRepos;
    };
  };

  _module.args.cgit = {
    inherit hostname assets;
    assetPaths = map (file: "/${file}") (builtins.attrNames assets.entries);
    config = cgitrc;
    socket = config.services.fcgiwrap.instances.cgit.socket.address;
    script = "${pkgs.cgit}/cgit/cgit.cgi";
  };
}
