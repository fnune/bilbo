{...}: let
  lan = "192.168.178.0/24";
in {
  # Immich, Calibre and Frigate are served on DNS-only records, so they bypass
  # Cloudflare Access and face the internet with nothing but their own login
  # form in front of them. None of the three locks an attacker out after
  # repeated failures the way Home Assistant now does.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "24h";
    ignoreIP = ["127.0.0.1/8" "::1" lan];

    jails.caddy-auth.settings = {
      enabled = true;
      filter = "caddy-auth";
      logpath = "/var/log/caddy/access-*.log";
      # Only web ports, so a ban can never cut off SSH recovery from the LAN.
      port = "http,https";
      maxretry = 5;
      bantime = "24h";
    };
  };

  # Caddy writes one JSON object per request. Verify against a real log with
  # `fail2ban-regex /var/log/caddy/access-home.fnune.com.log \
  #    /etc/fail2ban/filter.d/caddy-auth.conf` after rebuilding.
  environment.etc."fail2ban/filter.d/caddy-auth.conf".text = ''
    [Definition]
    failregex = ^\{.*"client_ip":"<HOST>".*"status":(?:401|403).*\}$
    datepattern = "ts":{EPOCH}
    ignoreregex =
  '';
}
