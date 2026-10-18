{
  caddyLogFile,
  config,
  lib,
  notify,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  appModule = {
    name,
    config,
    ...
  }: {
    options = {
      description = mkOption {type = types.str;};
      exposure = mkOption {
        type = types.enum ["vpn" "public"];
        default = "vpn";
        description = "vpn serves the app at bilbo.fnune.com/apps/<name>; public serves it at hostname, to the internet.";
      };
      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      basePath = mkOption {
        type = types.str;
        readOnly = true;
        default =
          if config.exposure == "vpn"
          then "/apps/${name}"
          else "";
        description = "The app must serve every route under this path: Caddy forwards it unchanged.";
      };
      site = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "A static site Caddy serves itself, instead of port and command.";
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
      };
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
      };
      credentials = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = "Files readable by the app under $CREDENTIALS_DIRECTORY/<name>.";
      };
      serviceConfig = mkOption {
        type = types.attrs;
        default = {};
      };
      rateLimit = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            paths = mkOption {type = types.listOf types.str;};
            perMinute = mkOption {type = types.ints.positive;};
          };
        });
        default = null;
        description = "Per-IP limit on the expensive routes of a public app.";
      };
      trafficAlert = {
        requestsPer5Minutes = mkOption {
          type = types.ints.positive;
          default = 3000;
        };
        serverErrorsPer5Minutes = mkOption {
          type = types.ints.positive;
          default = 50;
        };
      };
    };
  };

  apps = config.bilbo.apps;
  servedApps = lib.filterAttrs (_: app: app.site == null) apps;
  publicApps = lib.filterAttrs (_: app: app.exposure == "public") apps;

  quietPeriodMinutes = 60;

  trafficAlert = name: app: let
    log = caddyLogFile app.hostname;
    boundedTail = "tail --lines 200000 ${log}";
  in
    pkgs.writeShellApplication {
      name = "${name}-traffic-alert";
      runtimeInputs = [notify pkgs.coreutils pkgs.findutils pkgs.jq];
      text = ''
        stamp=$RUNTIME_DIRECTORY/notified
        [ -e ${log} ] || exit 0
        since=$(($(date +%s) - 300))
        read -r requests errors < <(${boundedTail} | jq -rn --argjson since "$since" '
          [inputs | select(.ts >= $since)]
          | "\(length) \(map(select(.status >= 500)) | length)"')
        if [ "$requests" -le ${toString app.trafficAlert.requestsPer5Minutes} ] && [ "$errors" -le ${toString app.trafficAlert.serverErrorsPer5Minutes} ]; then
          exit 0
        fi
        if [ -n "$(find "$stamp" -mmin -${toString quietPeriodMinutes} 2>/dev/null)" ]; then
          exit 0
        fi
        touch "$stamp"
        top=$(${boundedTail} | jq -rn --argjson since "$since" '
          [inputs | select(.ts >= $since) | .request.remote_ip]
          | group_by(.) | map({ip: .[0], n: length}) | sort_by(-.n) | .[:5]
          | map("\(.n) \(.ip)") | join("\n")')
        notify "${app.hostname} is busy" "$requests requests and $errors server errors in 5 minutes. Top addresses:
        $top" high
      '';
    };
in {
  options.bilbo.apps = mkOption {
    type = types.attrsOf (types.submodule appModule);
    default = {};
  };

  config = {
    assertions = lib.concatLists (lib.mapAttrsToList (name: app: [
        {
          assertion = (app.exposure == "public") == (app.hostname != null);
          message = "bilbo.apps.${name}: a public app needs a hostname, and only a public one has one.";
        }
        {
          assertion = (app.site != null) == (app.port == null && app.command == null);
          message = "bilbo.apps.${name}: set either site, or port and command.";
        }
      ])
      apps);

    users.users =
      lib.mapAttrs (name: _: {
        isSystemUser = true;
        group = name;
      })
      servedApps;
    users.groups = lib.mapAttrs (_: _: {}) servedApps;

    systemd.services =
      lib.mapAttrs (name: app: {
        inherit (app) description environment;
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig =
          {
            User = name;
            Group = name;
            StateDirectory = name;
            StateDirectoryMode = "0700";
            ExecStart = app.command;
            LoadCredential = lib.mapAttrsToList (credential: path: "${credential}:${path}") app.credentials;
            Restart = "always";
            RestartSec = 5;

            MemoryMax = "1G";
            CPUQuota = "100%";
            TasksMax = 256;

            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = ["@system-service" "~@privileged"];
            UMask = "0077";
          }
          // app.serviceConfig;
      })
      servedApps
      // lib.mapAttrs' (name: app:
        lib.nameValuePair "${name}-traffic-alert" {
          description = "Notify when ${app.hostname} gets unusual traffic";
          startAt = "*:0/5";
          serviceConfig = {
            Type = "oneshot";
            DynamicUser = true;
            SupplementaryGroups = [config.services.caddy.group];
            RuntimeDirectory = "${name}-traffic-alert";
            RuntimeDirectoryPreserve = true;
            ExecStart = lib.getExe (trafficAlert name app);
          };
        })
      publicApps;
  };
}
