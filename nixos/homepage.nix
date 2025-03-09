{...}: {
  services.homepage-dashboard = {
    enable = true;
    services = [
      {
        "Entertainment" = [
          {
            "Jellyfin" = {
              icon = "jellyfin.svg";
              description = "Media server for movies, TV shows, and music";
              href = "/jellyfin";
            };
          }
          {
            "Sonarr" = {
              icon = "sonarr.svg";
              description = "TV show management and automation";
              href = "/sonarr";
            };
          }
          {
            "Radarr" = {
              icon = "radarr.svg";
              description = "Movie collection manager and automation";
              href = "/radarr";
            };
          }
          {
            "Bazarr" = {
              icon = "bazarr.svg";
              description = "Subtitle downloader and manager";
              href = "/bazarr";
            };
          }
          {
            "Readarr" = {
              icon = "readarr.svg";
              description = "Book collection manager and automation";
              href = "/readarr";
            };
          }
          {
            "NZBGet" = {
              icon = "nzbget.svg";
              description = "Usenet downloader for media files";
              href = "/nzbget";
            };
          }
        ];
      }
      {
        "Monitoring" = [
          {
            "Grafana" = {
              icon = "grafana.svg";
              description = "Dashboard for metrics and system monitoring";
              href = "/grafana";
            };
          }
        ];
      }
    ];
  };
}
