{...}: {
  services.homepage-dashboard = {
    enable = true;
    settings = {
      title = "Bilbo";
      description = "My media server";
      headerStyle = "clean";
      target = "_self";
      hideVersion = true;
      color = "neutral";
      layout = {
        Entertainment = {
          style = "row";
        };
        Tools = {
          style = "row";
        };
      };
    };
    widgets = [
      {
        resources = {
          label = "System";
          cpu = true;
          memory = true;
          uptime = true;
          network = true;
        };
      }
      {
        resources = {
          label = "Replicated Storage";
          disk = "/mnt/mirrored";
        };
      }
      {
        resources = {
          label = "Movies & Books";
          disk = "/mnt/downloads-1t";
        };
      }
      {
        resources = {
          label = "Series";
          disk = "/mnt/downloads-2t";
        };
      }
    ];
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
        ];
      }
      {
        "Monitoring" = [
          {
            "Tools" = {
              icon = "grafana.svg";
              description = "Dashboard for metrics and system monitoring";
              href = "/grafana";
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
    ];
  };
}
