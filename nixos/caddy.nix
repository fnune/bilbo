{pkgs, ...}: let
  domain = "fnune.com";
  bilbo = "bilbo.${domain}";
  immich = "immich.${domain}";

  immichDyndns = pkgs.writeShellApplication {
    name = "immich-dyndns";
    runtimeInputs = with pkgs; [curl jq];
    text = ''
      TOKEN=$(cat /etc/cloudflare/token)
      IP=$(curl -sf https://api.ipify.org)

      ZONE_ID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
        "https://api.cloudflare.com/client/v4/zones?name=${domain}" | jq -r '.result[0].id')

      RECORD=$(curl -sf -H "Authorization: Bearer $TOKEN" \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=${immich}&type=A")

      RECORD_ID=$(echo "$RECORD" | jq -r '.result[0].id')

      if [ "$RECORD_ID" = "null" ]; then
        curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
          -d "{\"type\":\"A\",\"name\":\"${immich}\",\"content\":\"$IP\",\"proxied\":false}" \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"
      else
        curl -sf -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
          -d "{\"type\":\"A\",\"name\":\"${immich}\",\"content\":\"$IP\",\"proxied\":false}" \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID"
      fi
    '';
  };
in {
  networking.firewall = {
    allowedTCPPorts = [443];
    interfaces = {
      "eno1" = {
        allowedTCPPorts = [80];
      };
    };
  };

  systemd.services.immich-dyndns = {
    description = "Update Cloudflare DNS for ${immich} (DNS-only, no proxy)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    startAt = "*:0/5";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${immichDyndns}/bin/immich-dyndns";
    };
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/etc/cloudflare/caddy-env";

  services = {
    cloudflare-dyndns = {
      enable = true;
      proxied = true;
      domains = [bilbo];
      apiTokenFile = "/etc/cloudflare/token";
    };
    caddy = let
      cloudflareToken = "{$CLOUDFLARE_API_TOKEN}";
      tlsDnsCloudflare = ''
        tls {
          dns cloudflare ${cloudflareToken}
        }
      '';
      proxiesSupportingSubpath = ''
        reverse_proxy /grafana/* localhost:2342
        reverse_proxy /grafana localhost:2342

        reverse_proxy /nzbget/* localhost:6789
        reverse_proxy /nzbget localhost:6789

        reverse_proxy /radarr/* localhost:7878
        reverse_proxy /radarr localhost:7878

        reverse_proxy /sonarr/* localhost:8989
        reverse_proxy /sonarr localhost:8989

        reverse_proxy /bazarr/* 127.0.0.1:6767
        reverse_proxy /bazarr 127.0.0.1:6767

        reverse_proxy /readarr/* localhost:8787
        reverse_proxy /readarr localhost:8787

        reverse_proxy /filebrowser/* localhost:8080
        reverse_proxy /filebrowser localhost:8080

        reverse_proxy /jellyfin/* localhost:8096
        reverse_proxy /jellyfin localhost:8096

        reverse_proxy /pincho/* localhost:3210
        reverse_proxy /pincho localhost:3210

      '';
      rootIsHomepage = ''
        reverse_proxy /* localhost:8082
        reverse_proxy / localhost:8082
      '';
      rootIsImmich = ''
        reverse_proxy /* localhost:2283
        reverse_proxy / localhost:2283
      '';
      tlsOriginKey = ''
        tls /etc/cloudflare/origin-cert.pem /etc/cloudflare/origin-key.pem
      '';
    in {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
        hash = "sha256-4WF7tIx8d6O/Bd0q9GhMch8lS3nlR5N3Zg4ApA3hrKw=";
      };
      virtualHosts = {
        "${immich}".extraConfig = ''
          ${tlsDnsCloudflare}
          ${rootIsImmich}
        '';
        "${bilbo}".extraConfig = ''
          ${tlsOriginKey}
          ${rootIsHomepage}
          ${proxiesSupportingSubpath}
        '';
        ":80".extraConfig = ''
          ${proxiesSupportingSubpath}
          ${rootIsImmich}
        '';
      };
    };
  };
}
