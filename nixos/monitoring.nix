{
  config,
  lib,
  pkgs,
  ...
}: let
  ntfyHostname = "notify.fnune.com";
  ntfyListen = "127.0.0.1:2586";
  topic = "bilbo";

  beszelHostname = "health.fnune.com";
  beszelAgentListen = "127.0.0.1:45876";
  hubKey = "${config.services.beszel.hub.dataDir}/beszel_data/id_ed25519";

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

  smartdEvent = pkgs.writeShellScript "smartd-event" ''
    ${notify}/bin/notify "Disk problem: $SMARTD_DEVICESTRING" "$SMARTD_FULLMESSAGE" urgent
  '';
in {
  _module.args.notify = notify;

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
    };
    agent = {
      enable = true;
      smartmon.enable = true;
      extraPath = [pkgs.intel-gpu-tools];
      environment = {
        LISTEN = beszelAgentListen;
        KEY_FILE = "/run/beszel-agent/hub.pub";
        EXTRA_FILESYSTEMS = lib.concatStringsSep "," [
          "/mnt/downloads-1t__Movies & Books"
          "/mnt/downloads-2t__Series & Backups"
          "/mnt/mirrored__Mirror"
        ];
      };
    };
  };

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
}
