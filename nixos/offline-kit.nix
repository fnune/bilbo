{
  config,
  lib,
  offline-kit-storage,
  pkgs,
  ...
}: let
  app = config.bilbo.apps.offline-kit;
  stateDir = "/var/lib/offline-kit";
  downloadsDir = offline-kit-storage;

  silmaril = pkgs.mkSilmaril {
    inherit pkgs;
    modules = [
      {
        services.silmaril = {
          enable = true;
          inherit (app) port basePath;
          dataDir = stateDir;
          storage = lib.genAttrs ["archives" "maps" "models" "translation"] (kind: "${downloadsDir}/${kind}");

          library.archives =
            lib.genAttrs [
              "appropedia-en-all-maxi"
              "archlinux-en-all-maxi"
              "arduino-stackexchange-com-en-all"
              "based-cooking-en-all"
              "cd3wdproject-org-en-all"
              "cooking-stackexchange-com-en-all"
              "devdocs-en-bash"
              "devdocs-en-css"
              "devdocs-en-git"
              "devdocs-en-html"
              "devdocs-en-javascript"
              "devdocs-en-nix"
              "devdocs-en-node"
              "devdocs-en-python"
              "devdocs-en-react"
              "diy-stackexchange-com-en-all"
              "fas-military-medicine-en"
              "foss-cooking-en-all"
              "freecodecamp-en-all"
              "gardening-stackexchange-com-en-all"
              "gutenberg-en-lcc-s"
              "ham-stackexchange-com-en-all"
              "ifixit-en-all"
              "kochwiki-org-de-all-maxi"
              "librepathology-en-all-maxi"
              "libretexts-org-en-eng"
              "libretexts-org-en-math"
              "libretexts-org-en-med"
              "libretexts-org-en-phys"
              "mdwiki-en-all-maxi"
              "mechanics-stackexchange-com-en-all"
              "nhs-uk-en-medicines"
              "outdoors-stackexchange-com-en-all"
              "phet-mul-all"
              "raspberrypi-stackexchange-com-en-all"
              "robotics-stackexchange-com-en-all"
              "solar-lowtechmagazine-com-mul-all"
              "wikibooks-de-all-maxi"
              "wikibooks-en-all-maxi"
              "wikipedia-en-knots-maxi"
              "wikipedia-en-top1m-maxi"
              "wikivoyage-de"
              "wikivoyage-en"
              "wikivoyage-es"
              "wiktionary-de-all-nopic"
              "wiktionary-en-all-nopic"
              "wiktionary-en-simple-all-nopic"
              "wiktionary-es-all-nopic"
              "woodworking-stackexchange-com-en-all"
              "wwwnc-cdc-gov-en-all"
              "zimgit-food-preparation-en"
              "zimgit-knots-en"
              "zimgit-medicine-en"
              "zimgit-post-disaster-en"
              "zimgit-water-en"
            ] (_: {enable = true;})
            // {
              wikipedia-en = {
                enable = true;
                variant = "all-nopic";
              };
              wikipedia-de = {
                enable = true;
                variant = "nopic";
              };
              wikipedia-de-medicine = {
                enable = true;
                variant = "maxi";
              };
              wikipedia-es-medicine = {
                enable = true;
                variant = "maxi";
              };
              wikipedia-es = {
                enable = true;
                variant = "nopic";
              };
            };

          library.guides = lib.genAttrs [
            "bbk-checkliste-de"
            "bbk-checkliste-es"
            "bbk-ratgeber-de"
            "bbk-ratgeber-en"
            "bbk-ratgeber-es"
            "boe-rebt-es"
            "bwl-notvorrat-de"
            "erc-basic-life-support-en"
            "erc-first-aid-en"
            "erc-layperson-en"
            "industria-guia-bt-25-es"
            "msb-crisis-or-war-en"
            "pc-autoproteccion-es"
            "pc-inundaciones-es"
            "pc-plan-familiar-es"
          ] (_: {enable = true;});

          maps.regions = {
            world.enable = true;
            germany.enable = true;
            spain.enable = true;
            austria = {
              enable = true;
              maxzoom = 13;
            };
            france = {
              enable = true;
              maxzoom = 13;
            };
            switzerland = {
              enable = true;
              maxzoom = 13;
            };
          };

          ai = {
            models = ["qwen3.5:4b"];
            locale = "Germany";
          };
          translation.languages = ["de" "es"];
        };
      }
    ];
  };

  environment = {
    HOME = stateDir;
  };

  roomForTheChatModelOnCpu = {
    MemoryMax = "8G";
    CPUQuota = "300%";
  };
  serviceConfig =
    roomForTheChatModelOnCpu
    // {
      ExecStartPre = "+${pkgs.coreutils}/bin/install --directory --owner offline-kit --group offline-kit --mode 0700 ${downloadsDir}";
      ReadWritePaths = [downloadsDir];
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
    };
in {
  bilbo.apps.offline-kit = {
    description = "Offline kit - Wikipedia, maps, a chatbot and translation without the internet";
    port = 8380;
    command = lib.getExe silmaril;
    inherit environment serviceConfig;
  };

  systemd.services.offline-kit-fetch = {
    description = "Download everything the offline kit serves";
    after = ["offline-kit.service" "network-online.target"];
    wants = ["offline-kit.service" "network-online.target"];
    restartIfChanged = false;
    inherit environment;
    serviceConfig =
      config.systemd.services.offline-kit.serviceConfig
      // serviceConfig
      // {
        Type = "oneshot";
        ExecStart = "${silmaril}/bin/silmaril-fetch";
        Restart = "no";
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
      };
  };

  systemd.timers.offline-kit-fetch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnActiveSec = "5min";
      OnCalendar = "03:00";
      Persistent = true;
    };
  };
}
