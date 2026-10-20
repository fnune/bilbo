{
  lib,
  pkgs,
  ...
}: let
  hostname = "family.fnune.com";
  port = 5150;
  tree = "Núñez Alberro";

  grampsWebImage = "ghcr.io/gramps-project/grampsweb:26.10.1@sha256:4348222c2ab2f5c53f15e7e170bd8b17db1c1691326e0e72b0d0d6df87724b94";
  redisImage = "docker.io/library/redis:7.4.6-alpine@sha256:3b73847e72874be07e6657b129a94761662b79bc0f679273757d4218573b2a98";

  storage = "/var/lib/gramps-web";
  cache = "/var/cache/gramps-web";

  redisUrl = database: "redis://localhost:6379/${toString database}";
  sharesNetworkWithWeb = {
    dependsOn = ["grampsweb"];
    extraOptions = ["--network=container:grampsweb"];
  };
  environment = {
    GRAMPSWEB_TREE = tree;
    GRAMPSWEB_BASE_URL = "https://${hostname}";
    GRAMPSWEB_REGISTRATION_DISABLED = "True";
    GRAMPSWEB_MEDIA_BASE_DIR = "/family";
    GRAMPSWEB_CELERY_CONFIG__broker_url = redisUrl 0;
    GRAMPSWEB_CELERY_CONFIG__result_backend = redisUrl 0;
    GRAMPSWEB_RATELIMIT_STORAGE_URI = redisUrl 1;
  };
  volumes = [
    "${storage}/users:/app/users"
    "${storage}/secret:/app/secret"
    "${storage}/grampsdb:/root/.gramps/grampsdb"
    "${cache}/index:/app/indexdir"
    "${cache}/thumbnails:/app/thumbnail_cache"
    "${cache}/cache:/app/cache"
    "${cache}/tmp:/tmp"
    "${pkgs.familyData}:/family:ro"
  ];

  grampsTree = pkgs.runCommand "gramps-tree" {nativeBuildInputs = [pkgs.gramps];} ''
    export HOME=$TMPDIR
    mkdir $out
    cd ${pkgs.familyData}
    gramps --config=database.path:$out --create ${lib.escapeShellArg tree} --import tree/family.ged --yes
  '';
  treeDirectory = "${storage}/grampsdb/family";
in {
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      grampsweb = {
        image = grampsWebImage;
        ports = ["127.0.0.1:${toString port}:5000"];
        inherit environment volumes;
      };
      grampsweb-celery =
        sharesNetworkWithWeb
        // {
          image = grampsWebImage;
          cmd = ["celery" "-A" "gramps_webapi.celery" "worker" "--loglevel=INFO" "--concurrency=2"];
          inherit environment volumes;
        };
      grampsweb-redis =
        sharesNetworkWithWeb
        // {
          image = redisImage;
        };
    };
  };

  systemd = {
    services = {
      podman-grampsweb = {
        restartTriggers = [grampsTree];
        preStart = lib.mkBefore ''
          rm -rf ${treeDirectory}
          mkdir ${treeDirectory}
          cp -r --no-preserve=mode ${grampsTree}/*/. ${treeDirectory}/
        '';
        postStart = ''
          for _ in $(seq 60); do
            ${pkgs.podman}/bin/podman exec grampsweb test -s /app/secret/secret && break
            sleep 2
          done
          ${pkgs.podman}/bin/podman exec grampsweb sh -c 'GRAMPSWEB_SECRET_KEY="$(cat /app/secret/secret)" exec python3 -m gramps_webapi --config /app/config/config.cfg search index-full'
        '';
      };
      podman-grampsweb-celery = {
        bindsTo = ["podman-grampsweb.service"];
        partOf = ["podman-grampsweb.service"];
      };
      podman-grampsweb-redis = {
        bindsTo = ["podman-grampsweb.service"];
        partOf = ["podman-grampsweb.service"];
      };
    };
    tmpfiles.rules =
      map (d: "d ${storage}/${d} 0700 root root -") ["" "users" "secret" "grampsdb"]
      ++ map (d: "d ${cache}/${d} 0700 root root -") ["" "index" "thumbnails" "cache" "tmp"];
  };

  bilbo.backups.gramps-web = {
    paths = [storage];
    exclude = ["${storage}/grampsdb"];
  };

  _module.args.family = {
    inherit hostname port;
    map = pkgs.familyMap.override {grampsUrl = "https://${hostname}";};
  };
}
