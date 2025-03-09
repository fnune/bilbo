{config, ...}: {
  services = {
    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 2342;
          root_url = "http://localhost:2342/grafana";
          serve_from_sub_path = true;
        };
      };
    };
    prometheus = {
      enable = true;
      exporters = {
        # Consider importing some nice premade dashboards:
        # https://raw.githubusercontent.com/rfmoz/grafana-dashboards/master/prometheus/node-exporter-full.json
        node = {
          enable = true;
          enabledCollectors = ["systemd"];
        };
      };
      scrapeConfigs = [
        {
          job_name = "bilbo";
          static_configs = [
            {
              targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
            }
          ];
        }
      ];
    };
  };
}
