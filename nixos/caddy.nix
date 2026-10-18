{
  bilboToolsCommand,
  config,
  pkgs,
  lib,
  crowdsec,
  trafficReportSite,
  servarrAddress,
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
  publicIpAlias = host "ip";
  dyndnsHosts = builtins.attrValues public ++ [vpnEndpoint publicIpAlias];

  vpnApps = lib.filterAttrs (_: app: app.exposure == "vpn") config.bilbo.apps;
  publicApps = lib.filterAttrs (_: app: app.exposure == "public") config.bilbo.apps;
  publicHostnames = builtins.attrValues public ++ lib.mapAttrsToList (_: app: app.hostname) publicApps;

  vpnSubnet = "10.100.0.0/24";

  logFile = hostname: "${config.services.caddy.logDir}/access-${hostname}.log";
  publicLogs = map logFile publicHostnames;

  immichPort = toString config.services.immich.port;
  sharedPhotosPort = toString config.services.immich-public-proxy.port;
  papraPort = toString config.services.papra.environment.PORT;
  beszelPort = toString config.services.beszel.hub.port;
  ntfyListen = config.services.ntfy-sh.settings.listen-http;
  seerrPort = toString config.services.seerr.port;
in {
  _module.args = {
    caddyPublicLogs = publicLogs;
    caddyLogFile = logFile;
  };

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

  systemd.services = {
    dyndns = {
      description = "Point the public hostnames at the household address";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      startAt = "*:0/5";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = bilboToolsCommand "dyndns" {
          addressUrl = "https://api.ipify.org";
          zone = domain;
          hostnames = dyndnsHosts;
        };
        LoadCredential = ["cloudflare-dns-token:${config.sops.secrets.cloudflare-dns-token.path}"];
      };
    };

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
    inOurDnsZone = hostname: lib.hasSuffix ".${domain}" hostname;
    tlsFor = hostname: lib.optionalString (inOurDnsZone hostname) tlsDnsCloudflare;
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
    atSubpath = path: upstream: ''
      reverse_proxy /${path}/* ${upstream}
      reverse_proxy /${path} ${upstream}
    '';
    staticAtSubpath = path: site: ''
      redir /${path} /${path}/ 308
      handle_path /${path}/* {
        root * ${site}
        file_server
      }
    '';
    appAtSubpath = path: app:
      if app.site != null
      then staticAtSubpath path app.site
      else atSubpath path "127.0.0.1:${toString app.port}";
    jellyfinAtSubpath = atSubpath "jellyfin" "localhost:8096";
    adminSubpaths = ''
      ${atSubpath "nzbget" "localhost:6789"}
      ${atSubpath "radarr" (servarrAddress "radarr")}
      ${atSubpath "sonarr" (servarrAddress "sonarr")}
      ${atSubpath "prowlarr" (servarrAddress "prowlarr")}
      ${atSubpath "bazarr" "127.0.0.1:${toString config.services.bazarr.listenPort}"}
      ${calibreAtSubpath}
      ${jellyfinAtSubpath}
      redir /smb* /apps/smb/ 308
      ${lib.concatMapAttrsStringSep "\n" (name: app: appAtSubpath "apps/${name}" app) vpnApps}
      ${staticAtSubpath "traffic" trafficReportSite}
      ${atSubpath "zigbee2mqtt" "localhost:8085"}

      @startPage path / /icons/*
      handle @startPage {
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
        ${tlsFor hostname}
        route {
          crowdsec
          ${handlers}
        }
      '';
    };
    rateLimit = name: limit: ''
      rate_limit {
        zone ${name} {
          match {
            path ${lib.concatStringsSep " " limit.paths}
          }
          key {remote_host}
          events ${toString limit.perMinute}
          window 1m
        }
      }
    '';
    publicAppSites = lib.mapAttrs' (name: app:
      lib.nameValuePair app.hostname (publicSite app.hostname ''
        ${lib.optionalString (app.rateLimit != null) (rateLimit name app.rateLimit)}
        ${
          if app.site != null
          then "root * ${app.site}\nfile_server"
          else rootIs "127.0.0.1:${toString app.port}"
        }
      ''))
    publicApps;
  in {
    enable = true;
    # nixpkgs' install check can't find plugins that live in a subfolder of their repo, like the bouncer.
    package = (pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.4"
        "github.com/hslatman/caddy-crowdsec-bouncer/http@v0.9.2"
        # The bouncer's own ipstore version doesn't build with the one Caddy pulls in.
        "github.com/hslatman/ipstore@v0.5.0"
        "github.com/mholt/caddy-ratelimit@v0.1.1-0.20260612195517-5625512f24f6"
      ];
      hash = "sha256-fizI2dUvfM1xtMdm1LLlCv2brhjA+3ukJRXDeLWYX7w=";
    }).overrideAttrs {doInstallCheck = false;};
    globalConfig = ''
      crowdsec {
        api_url ${crowdsec.lapiUrl}
        # Caddy won't start with an empty key, so the default keeps every site up until the bouncer registers.
        # https://caddyserver.com/docs/caddyfile/concepts#environment-variables
        api_key {$CROWDSEC_API_KEY:unregistered}
      }
    '';
    virtualHosts =
      publicAppSites
      // {
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
