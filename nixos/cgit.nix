{
  config,
  forgejo,
  lib,
  pkgs,
  ...
}: let
  hostname = "code.fnune.com";
  mirrors = "/var/lib/cgit";
  cache = "/var/cache/cgit";

  publicRepos = {};

  forgejoRepository = name: "${forgejo.repositories}/${forgejo.username}/${lib.toLower name}.git";
  mirror = name: "${mirrors}/${name}.git";
  publishedRefs = ["+refs/heads/*:refs/heads/*" "+refs/tags/*:refs/tags/*"];

  assets =
    pkgs.linkFarm "cgit-assets" (lib.genAttrs ["cgit.css" "cgit.png" "favicon.ico" "robots.txt"] (file: "${pkgs.cgit}/cgit/${file}")
      // {"forgejo-link.js" = ./cgit/forgejo-link.js;});

  headInclude = pkgs.writeText "cgit-head.html" ''
    <script src="/forgejo-link.js" defer></script>
  '';

  filters = "${pkgs.cgit}/lib/cgit/filters";

  globalSettings = ''
    root-title=fnune's code
    root-desc=Public repositories, mirrored from my own forge
    virtual-root=/
    css=/cgit.css
    logo=/cgit.png
    favicon=/favicon.ico
    head-include=${headInclude}
    clone-url=https://${hostname}/$CGIT_REPO_URL
    enable-http-clone=1
    enable-index-owner=0
    enable-commit-graph=1
    enable-log-filecount=1
    cache-root=${cache}
    cache-size=1000
    readme=:README.md
    readme=:readme.md
    readme=:README
    about-filter=${filters}/about-formatting.sh
    source-filter=${filters}/syntax-highlighting.py
  '';
  repoSections = lib.concatStrings (lib.mapAttrsToList (name: repo: ''
      repo.url=${name}
      repo.path=${mirror name}
      repo.desc=${repo.desc}
    '')
    publicRepos);
  cgitrc = pkgs.writeText "cgitrc" (globalSettings + repoSections);

  sync = pkgs.writeShellApplication {
    name = "cgit-sync";
    runtimeInputs = [pkgs.coreutils pkgs.git];
    text = ''
      declare -A wanted=(${lib.concatMapAttrsStringSep " " (name: _: "[${lib.escapeShellArg name}]=${lib.escapeShellArg (forgejoRepository name)}") publicRepos})

      for name in "''${!wanted[@]}"; do
        source=''${wanted[$name]}
        target=${mirrors}/$name.git
        [ -d "$target" ] || git init --quiet --bare "$target"
        git -C "$target" fetch --quiet --prune "$source" ${lib.escapeShellArgs publishedRefs}
        git -C "$target" symbolic-ref HEAD "$(git -C "$source" symbolic-ref HEAD)"
        git -C "$target" update-server-info
      done

      for target in ${mirrors}/*.git; do
        [ -e "$target" ] || continue
        name=$(basename "$target" .git)
        [ -v "wanted[$name]" ] || rm -rf "$target"
      done
    '';
  };
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

  systemd.services = {
    fcgiwrap-cgit.serviceConfig = {
      CacheDirectory = "cgit";
      Nice = 10;
    };

    cgit-sync = {
      description = "Copy the public repositories from Forgejo for cgit";
      after = ["forgejo.service"];
      startAt = "*:0/10";
      unitConfig.RequiresMountsFor = [forgejo.repositories];
      serviceConfig = {
        Type = "oneshot";
        User = config.services.forgejo.user;
        Group = "cgit";
        StateDirectory = "cgit";
        StateDirectoryMode = "0750";
        UMask = "0027";
        ExecStart = lib.getExe sync;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
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
