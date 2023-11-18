{config, ...}: let
  grafanaPort = 2342;
in {
  networking.firewall.allowedTCPPorts = [grafanaPort];
  services = {
    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = grafanaPort;
          domain = "localhost";
        };
      };
    };
    prometheus = {
      enable = true;
      exporters = {
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
