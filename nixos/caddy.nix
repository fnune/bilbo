{
  config,
  pkgs,
  lib,
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
  };

  public = {
    sharedPhotos = host "photos";
    koboSync = host "calibre";
    guestJellyfin = host "watch";
  };
  vpnEndpoint = host "wireguard";
  dyndnsHosts = builtins.attrValues public ++ [vpnEndpoint];

  vpnSubnet = "10.100.0.0/24";

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
in {
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
      caddy.serviceConfig.EnvironmentFile = config.sops.templates."caddy.env".path;
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

      ${calibreAtSubpath}

      ${jellyfinAtSubpath}

      reverse_proxy /pincho/* localhost:3210
      reverse_proxy /pincho localhost:3210

      reverse_proxy /zigbee2mqtt/* localhost:8085
      reverse_proxy /zigbee2mqtt localhost:8085

      reverse_proxy /smb/* localhost:8799
      reverse_proxy /smb localhost:8799

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
  in {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
      hash = "sha256-xRJ5evsAJ2akg47j3Bt6YDXJOgX88B/rKNP50KSVyNY=";
    };
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

      "${public.sharedPhotos}".extraConfig = ''
        ${tlsDnsCloudflare}
        ${rootIs "localhost:${sharedPhotosPort}"}
      '';
      # The token in the Kobo sync URL is its login.
      "${public.koboSync}".extraConfig = ''
        ${tlsDnsCloudflare}
        route {
          reverse_proxy /kobo/* 127.0.0.1:8083 {
            header_up X-Scheme {scheme}
          }
          respond 404
        }
      '';
      "${public.guestJellyfin}".extraConfig = ''
        ${tlsDnsCloudflare}
        route {
          redir / /jellyfin/ 302
          ${jellyfinAtSubpath}
          respond 404
        }
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
