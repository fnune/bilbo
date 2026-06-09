{...}: {
  systemd.services.lazylibrarian-init = {
    description = "Pre-seed LazyLibrarian config.ini with HTTP_ROOT before container start";
    wantedBy = ["podman-lazylibrarian.service"];
    before = ["podman-lazylibrarian.service"];
    serviceConfig.Type = "oneshot";
    script = ''
            install -d -m 755 -o fausto -g users /var/lib/lazylibrarian
            if [ ! -f /var/lib/lazylibrarian/config.ini ]; then
              cat >/var/lib/lazylibrarian/config.ini <<'EOF'
      [General]
      HTTP_ROOT = /lazylibrarian
      HTTP_HOST = 0.0.0.0
      HTTP_PORT = 5299
      EOF
              chown fausto:users /var/lib/lazylibrarian/config.ini
            fi
    '';
  };

  virtualisation.oci-containers.containers.lazylibrarian = {
    image = "lscr.io/linuxserver/lazylibrarian:latest";
    autoStart = true;
    ports = ["127.0.0.1:5299:5299"];
    volumes = [
      "/var/lib/lazylibrarian:/config"
      "/mnt/downloads-1t/Books:/books"
      "/mnt/downloads-1t/Books:/downloads"
    ];
    environment = {
      PUID = "1000";
      PGID = "100";
      TZ = "Europe/Berlin";
      DOCKER_MODS = "linuxserver/mods:lazylibrarian-calibre";
    };
  };
}
