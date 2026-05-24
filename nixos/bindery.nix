{...}: {
  virtualisation.docker.enable = true;

  virtualisation.oci-containers.containers.bindery = {
    image = "ghcr.io/vavallee/bindery:latest";
    autoStart = true;
    ports = ["127.0.0.1:8787:8787"];
    volumes = [
      "/var/lib/bindery:/config"
      "/mnt/downloads-1t/Books:/books"
      "/mnt/downloads-1t/Books:/downloads"
    ];
    environment = {
      BINDERY_LOG_LEVEL = "info";
      BINDERY_URL_BASE = "/bindery";
      BINDERY_PUID = "1000";
      BINDERY_PGID = "100";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/bindery 0755 fausto users -"
  ];
}
