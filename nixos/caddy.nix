{
  config,
  pkgs,
  lib,
  crowdsec,
  ...
}: let
  domain = "fnune.com";
  host = name: "${name}.${domain}";

  vpnOnly = {
    admin = host "bilbo";
    immich = host "immich";
    frigate = host "frigate";
    homeAssistant = host "home";
    papra = host "docs";
    health = host "health";
    notify = host "notify";
    requests = host "requests";
  };

  public = {
    sharedPhotos = host "photos";
    koboSync = host "calibre";
    guestJellyfin = host "watch";
  };
  vpnEndpoint = host "wireguard";
  dyndnsHosts = builtins.attrValues public ++ [vpnEndpoint];

  vpnSubnet = "10.100.0.0/24";

  logFile = hostname: "${config.services.caddy.logDir}/access-${hostname}.log";
  publicLogs = map logFile (builtins.attrValues public);

  dnsToken = config.sops.secrets.cloudflare-dns-token.path;

  mkDyndns = hostname: let
    slug = lib.replaceStrings ["."] ["-"] hostname;
  in
    pkgs.writeShellApplication {
      name = "dyndns-${slug}";
      runtimeInputs = with pkgs; [curl jq];
      text = ''
        TOKEN=$(cat ${dnsToken})
        IP=$(curl -sf https://api.ipify.org)

        ZONE_ID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
          "https://api.cloudflare.com/client/v4/zones?name=${domain}" | jq -r '.result[0].id')

        RECORD=$(curl -sf -H "Authorization: Bearer $TOKEN" \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=${hostname}&type=A")

        RECORD_ID=$(echo "$RECORD" | jq -r '.result[0].id')

        if [ "$RECORD_ID" = "null" ]; then
          curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"${hostname}\",\"content\":\"$IP\",\"proxied\":false}" \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"
        else
          curl -sf -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"${hostname}\",\"content\":\"$IP\",\"proxied\":false}" \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID"
        fi
      '';
    };

  mkDyndnsService = hostname: let
    slug = lib.replaceStrings ["."] ["-"] hostname;
    app = mkDyndns hostname;
  in {
    name = "dyndns-${slug}";
    value = {
      description = "Update Cloudflare DNS for ${hostname} (DNS-only, no proxy)";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      startAt = "*:0/5";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${app}/bin/dyndns-${slug}";
      };
    };
  };

  immichPort = toString config.services.immich.port;
  sharedPhotosPort = toString config.services.immich-public-proxy.port;
  papraPort = toString config.services.papra.environment.PORT;
  beszelPort = toString config.services.beszel.hub.port;
  ntfyListen = config.services.ntfy-sh.settings.listen-http;
  seerrPort = toString config.services.seerr.port;
  prowlarrPort = toString config.services.prowlarr.settings.server.port;
in {
  _module.args.caddyPublicLogs = publicLogs;

  # CrowdSec reads these through the caddy group; tmpfiles fixes files Caddy created before.
  systemd.tmpfiles.rules = map (log: "z ${log} 0640 caddy caddy -") publicLogs;

  networking.firewall = {
    allowedTCPPorts = [443];
    interfaces = {
      "eno1" = {
        allowedTCPPorts = [80];
      };
    };
  };

  sops = {
    secrets.cloudflare-dns-token = {};
    templates."caddy.env" = {
      owner = config.services.caddy.user;
      content = "CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare-dns-token}";
    };
  };

  systemd.services =
    (lib.listToAttrs (map mkDyndnsService dyndnsHosts))
    // {
      caddy = {
        after = ["crowdsec-caddy-bouncer-register.service"];
        wants = ["crowdsec-caddy-bouncer-register.service"];
        serviceConfig.EnvironmentFile = [
          config.sops.templates."caddy.env".path
          "-${crowdsec.bouncerEnv}"
        ];
      };
    };

  services.caddy = let
    tlsDnsCloudflare = ''
      tls {
        dns cloudflare {$CLOUDFLARE_API_TOKEN}
      }
    '';
    outsideVpn = ''
      @outsideVpn not remote_ip ${vpnSubnet} 127.0.0.1/8 ::1
    '';
    calibreAtSubpath = ''
      redir /calibre /calibre/ 308
      reverse_proxy /calibre/* 127.0.0.1:8083 {
        header_up X-Script-Name /calibre
        header_up X-Scheme {scheme}
        header_up X-Forwarded-Host {host}
      }
    '';
    jellyfinAtSubpath = ''
      reverse_proxy /jellyfin/* localhost:8096
      reverse_proxy /jellyfin localhost:8096
    '';
    adminSubpaths = ''
      reverse_proxy /nzbget/* localhost:6789
      reverse_proxy /nzbget localhost:6789

      reverse_proxy /radarr/* localhost:7878
      reverse_proxy /radarr localhost:7878

      reverse_proxy /sonarr/* localhost:8989
      reverse_proxy /sonarr localhost:8989

      reverse_proxy /bazarr/* 127.0.0.1:6767
      reverse_proxy /bazarr 127.0.0.1:6767

      reverse_proxy /prowlarr/* 127.0.0.1:${prowlarrPort}
      reverse_proxy /prowlarr 127.0.0.1:${prowlarrPort}

      ${calibreAtSubpath}

      ${jellyfinAtSubpath}

      reverse_proxy /pincho/* localhost:3210
      reverse_proxy /pincho localhost:3210

      reverse_proxy /zigbee2mqtt/* localhost:8085
      reverse_proxy /zigbee2mqtt localhost:8085

      reverse_proxy /smb/* localhost:8799
      reverse_proxy /smb localhost:8799

      handle / {
        root * ${./start-page}
        file_server
      }

      respond 404
    '';
    # route keeps the written order; Caddy would otherwise run respond and abort after reverse_proxy
    vpnOnlyRoute = handlers: ''
      ${outsideVpn}
      route {
        abort @outsideVpn
        ${handlers}
      }
    '';
    rootIs = upstream: ''
      reverse_proxy /* ${upstream}
      reverse_proxy / ${upstream}
    '';
    publicSite = hostname: handlers: {
      logFormat = ''
        output file ${logFile hostname} {
          mode 0640
        }
      '';
      extraConfig = ''
        ${tlsDnsCloudflare}
        route {
          crowdsec
          ${handlers}
        }
      '';
    };
  in {
    enable = true;
    # The install check looks for each plugin's module path in the build info, and the bouncer lives in a subdirectory of its module.
    package = (pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.4"
        "github.com/hslatman/caddy-crowdsec-bouncer/http@v0.9.2"
        # The bouncer's v0.3.0 pin of ipstore does not build against the bart version Caddy pulls in.
        "github.com/hslatman/ipstore@v0.5.0"
      ];
      hash = "sha256-7nQ2ikk0ugapEp0NdLZqGbQlxfSZRO7pAV2UAIy2RwE=";
    }).overrideAttrs {doInstallCheck = false;};
    globalConfig = ''
      crowdsec {
        api_url ${crowdsec.lapiUrl}
        # A placeholder keeps Caddy starting while the bouncer is unregistered; it then lets traffic through.
        api_key {$CROWDSEC_API_KEY:unregistered}
      }
    '';
    virtualHosts = {
      "${vpnOnly.admin}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute adminSubpaths}
      '';
      "${vpnOnly.immich}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs "localhost:${immichPort}")}
      '';
      "${vpnOnly.frigate}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs "localhost:8971")}
      '';
      "${vpnOnly.homeAssistant}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs "localhost:8123")}
      '';
      "${vpnOnly.papra}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs "127.0.0.1:${papraPort}")}
      '';
      "${vpnOnly.health}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs "127.0.0.1:${beszelPort}")}
      '';
      "${vpnOnly.notify}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs ntfyListen)}
      '';
      "${vpnOnly.requests}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${vpnOnlyRoute (rootIs "localhost:${seerrPort}")}
      '';

      "${public.sharedPhotos}" = publicSite public.sharedPhotos (rootIs "localhost:${sharedPhotosPort}");
      # The token in the Kobo sync URL is its login.
      "${public.koboSync}" = publicSite public.koboSync ''
        reverse_proxy /kobo/* 127.0.0.1:8083 {
          header_up X-Scheme {scheme}
        }
        respond 404
      '';
      "${public.guestJellyfin}" = publicSite public.guestJellyfin ''
        redir / /jellyfin/ 302
        ${jellyfinAtSubpath}
        respond 404
      '';

      ":80".extraConfig = ''
        @lan remote_ip private_ranges
        handle @lan {
          route {
            ${adminSubpaths}
          }
        }
        handle {
          redir https://{host}{uri} permanent
        }
      '';
    };
  };
}
