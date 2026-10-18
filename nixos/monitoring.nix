{
  caddyPublicLogs,
  config,
  lib,
  mkSettingsService,
  pkgs,
  ...
}: let
  ntfyHostname = "notify.fnune.com";
  ntfyListen = "127.0.0.1:2586";
  topic = "bilbo";

  beszelHostname = "health.fnune.com";
  beszelAgentHost = "127.0.0.1";
  beszelAgentPort = 45876;
  beszelData = "${config.services.beszel.hub.dataDir}/beszel_data";
  hubKey = "${beszelData}/id_ed25519";
  systemsSyncedOnHubStart = (pkgs.formats.yaml {}).generate "beszel-config.yml" {
    systems = [
      {
        name = config.networking.hostName;
        host = beszelAgentHost;
        port = beszelAgentPort;
      }
    ];
  };

  notify = pkgs.writeShellApplication {
    name = "notify";
    runtimeInputs = [pkgs.curl];
    text = ''
      title=$1
      message=$2
      priority=''${3:-default}
      curl --silent --show-error --fail --max-time 10 \
        -H "Title: $title" \
        -H "Priority: $priority" \
        --data-binary "$message" \
        http://${ntfyListen}/${topic}
    '';
  };

  quietPeriodMinutes = 60;

  notifyFailure = pkgs.writeShellApplication {
    name = "notify-failure";
    runtimeInputs = [notify pkgs.coreutils pkgs.findutils pkgs.systemd];
    text = ''
      unit=$1
      stamp=/run/notify-failure/$unit
      if [ -n "$(find "$stamp" -mmin -${toString quietPeriodMinutes} 2>/dev/null)" ]; then
        exit 0
      fi
      touch "$stamp"
      notify "$unit failed" "$(journalctl --unit "$unit" --lines 15 --no-pager --output cat)" high
    '';
  };

  notifyOnAnyServiceFailure = pkgs.writeTextDir "etc/systemd/system/service.d/10-notify-on-failure.conf" ''
    [Unit]
    OnFailure=notify-failure@%N.service
  '';
  failureHandlerNeverNotifiesAboutItself = pkgs.writeTextDir "etc/systemd/system/notify-failure@.service.d/10-no-recursion.conf" ''
    [Unit]
    OnFailure=
  '';

  shortSelfTestNightly = "S/../.././02";
  longSelfTestMonthly = "L/../01/./04";

  trafficReportDir = "/var/lib/traffic-report";
  trafficReportSite = "${trafficReportDir}/site";
  trafficReport = pkgs.writeShellApplication {
    name = "traffic-report";
    runtimeInputs = [pkgs.coreutils pkgs.goaccess];
    text = ''
      logs=()
      for log in ${lib.escapeShellArgs caddyPublicLogs}; do
        [ -e "$log" ] && logs+=("$log")
      done
      [ ''${#logs[@]} -gt 0 ] || exit 0
      mkdir -p ${trafficReportDir}/db ${trafficReportSite}
      goaccess "''${logs[@]}" --log-format CADDY --persist --restore --db-path ${trafficReportDir}/db \
        --html-report-title "Public traffic" --no-progress --output ${trafficReportSite}/index.html
    '';
  };

  smartdEvent = pkgs.writeShellScript "smartd-event" ''
    ${notify}/bin/notify "Disk problem: $SMARTD_DEVICESTRING" "$SMARTD_FULLMESSAGE" urgent
  '';
in {
  _module.args = {
    inherit notify trafficReportSite;
  };

  systemd.services.traffic-report = {
    description = "Update the report of traffic to the public hostnames";
    startAt = "*:0/10";
    serviceConfig = {
      Type = "oneshot";
      User = config.services.caddy.user;
      Group = config.services.caddy.group;
      StateDirectory = "traffic-report";
      ExecStart = lib.getExe trafficReport;
    };
  };

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://${ntfyHostname}";
      listen-http = ntfyListen;
      behind-proxy = true;
    };
  };

  systemd.packages = [notifyOnAnyServiceFailure failureHandlerNeverNotifiesAboutItself];
  systemd.services."notify-failure@" = {
    description = "Notify that %i failed";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${notifyFailure}/bin/notify-failure %i";
      RuntimeDirectory = "notify-failure";
      RuntimeDirectoryPreserve = true;
    };
  };

  services.smartd = {
    enable = true;
    notifications = {
      mail.enable = false;
      wall.enable = false;
      x11.enable = false;
    };
    defaults.monitored = "-a -o on -s (${shortSelfTestNightly}|${longSelfTestMonthly}) -m <nomailer> -M exec ${smartdEvent}";
  };

  services.beszel = {
    hub = {
      enable = true;
      environment.APP_URL = "https://${beszelHostname}";
      environmentFile = config.sops.templates."beszel-hub.env".path;
    };
    agent = {
      enable = true;
      smartmon.enable = true;
      extraPath = [pkgs.intel-gpu-tools];
      environment = {
        LISTEN = "${beszelAgentHost}:${toString beszelAgentPort}";
        KEY_FILE = "/run/beszel-agent/hub.pub";
        EXTRA_FILESYSTEMS = lib.concatStringsSep "," [
          "/mnt/downloads-1t__Movies & Books"
          "/mnt/downloads-2t__Series & Backups"
          "/mnt/mirrored__Mirror"
        ];
      };
    };
  };

  systemd.services.beszel-hub.preStart = ''
    mkdir -p ${beszelData}
    ln -sf ${systemsSyncedOnHubStart} ${beszelData}/config.yml
  '';

  systemd.services.beszel-agent = {
    after = ["beszel-hub.service"];
    wants = ["beszel-hub.service"];
    unitConfig.RequiresMountsFor = ["/mnt/downloads-1t" "/mnt/downloads-2t" "/mnt/mirrored"];
    serviceConfig = {
      RuntimeDirectory = "beszel-agent";
      ExecStartPre = "+${pkgs.writeShellScript "beszel-agent-wait-for-hub-key" ''
        for _ in $(seq 60); do
          [ -s ${hubKey} ] && break
          sleep 1
        done
        ${pkgs.openssh}/bin/ssh-keygen -y -f ${hubKey} > /run/beszel-agent/hub.pub
        chmod 0644 /run/beszel-agent/hub.pub
      ''}";
      AmbientCapabilities = ["CAP_PERFMON"];
      CapabilityBoundingSet = ["CAP_PERFMON"];
    };
  };

  sops = {
    secrets = lib.genAttrs ["beszel-email" "beszel-password"] (_: {});
    templates."beszel-hub.env".content = ''
      BESZEL_HUB_USER_EMAIL=${config.sops.placeholder.beszel-email}
      BESZEL_HUB_USER_PASSWORD=${config.sops.placeholder.beszel-password}
    '';
  };

  systemd.services.beszel-hub.serviceConfig.ExecStartPost = pkgs.writeShellScript "beszel-superuser-from-sops" ''
    ${config.services.beszel.hub.package}/bin/beszel-hub --dir ${beszelData} \
      superuser upsert "$BESZEL_HUB_USER_EMAIL" "$BESZEL_HUB_USER_PASSWORD"
  '';

  systemd.services.beszel-settings = mkSettingsService {
    name = "beszel-settings";
    description = "Apply Beszel's user, notification and alert settings from this repository";
    after = ["beszel-hub"];
    secrets = ["beszel-email" "beszel-password"];
    settings = {
      url = "http://127.0.0.1:${toString config.services.beszel.hub.port}";
      system = config.networking.hostName;
      webhook = "ntfy://${ntfyListen}/${topic}?scheme=http";
      alerts = [
        {
          name = "Status";
          value = 0;
          min = 2;
        }
        {
          name = "Disk";
          value = 85;
          min = 10;
        }
        {
          name = "Temperature";
          value = 80;
          min = 10;
        }
        {
          name = "Bandwidth";
          value = 100;
          min = 10;
        }
      ];
    };
  };
}
