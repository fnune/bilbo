{
  config,
  forgejo,
  lib,
  pkgs,
  ...
}: let
  hostname = "code.fnune.com";

  publicRepos = "/run/cgit/public-repos";
  bindMountsDropIn = "/run/systemd/system/fcgiwrap-cgit.service.d/public-repos.conf";

  assets = pkgs.linkFarm "cgit-assets" (lib.genAttrs ["cgit.css" "cgit.png" "favicon.ico" "robots.txt"] (file: "${pkgs.cgit}/cgit/${file}"));

  filters = "${pkgs.cgit}/lib/cgit/filters";

  cgitrc = pkgs.writeText "cgitrc" ''
    root-title=fnune's code
    root-desc=Public repositories
    enable-index-owner=0
    virtual-root=/
    css=/cgit.css
    logo=/cgit.png
    favicon=/favicon.ico
    mimetype-file=${pkgs.mailcap}/etc/mime.types
    readme=:README.md
    about-filter=${filters}/about-formatting.sh
    source-filter=${filters}/syntax-highlighting.py
    include=${publicRepos}
  '';

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
    };
  };

  systemd.services.cgit-public-repos = {
    description = "Show Forgejo's public repositories on cgit";
    after = ["forgejo.service"];
    wantedBy = ["multi-user.target"];
    startAt = "daily";
    path = [pkgs.diffutils pkgs.sqlite pkgs.systemd];
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "cgit";
      RuntimeDirectoryPreserve = true;
    };
    script = ''
      publicRepos() {
        sqlite3 -readonly -cmd '.timeout 10000' -separator $'\t' ${lib.escapeShellArg forgejo.database} \
          "SELECT name, lower_name, replace(replace(replace(description, char(9), ' '), char(10), ' '), char(13), ' ')
           FROM repository WHERE owner_name = '${forgejo.username}' AND NOT is_private ORDER BY lower_name"
      }

      show() {
        cgitrc=$(mktemp) dropIn=$(mktemp)
        echo '[Service]' > "$dropIn"
        while IFS=$'\t' read -r name lowerName description; do
          [ -n "$name" ] || continue
          path=${forgejo.repositories}/${forgejo.username}/$lowerName.git
          printf 'repo.url=%s\nrepo.path=%s\nrepo.desc=%s\n' "$name" "$path" "$description" >> "$cgitrc"
          echo "BindReadOnlyPaths=-$path" >> "$dropIn"
        done <<< "$1"

        install -m 0644 "$cgitrc" ${publicRepos}
        if ! cmp --quiet "$dropIn" ${bindMountsDropIn}; then
          install -D -m 0644 "$dropIn" ${bindMountsDropIn}
          systemctl daemon-reload
          systemctl try-restart fcgiwrap-cgit.service
        fi
        rm "$cgitrc" "$dropIn"
      }

      showUntilNothingChangedMeanwhile() {
        local shown latest
        latest=$(publicRepos)
        while [ "''${shown-unset}" != "$latest" ]; do
          show "$latest"
          shown=$latest
          latest=$(publicRepos)
        done
      }

      showUntilNothingChangedMeanwhile
    '';
  };

  systemd.paths.cgit-public-repos = {
    wantedBy = ["multi-user.target"];
    pathConfig.PathModified = [forgejo.database "${forgejo.database}-wal"];
  };

  _module.args.cgit = {
    inherit hostname assets;
    assetPaths = map (file: "/${file}") (builtins.attrNames assets.entries);
    config = cgitrc;
    socket = config.services.fcgiwrap.instances.cgit.socket.address;
    script = "${pkgs.cgit}/cgit/cgit.cgi";
  };
}
