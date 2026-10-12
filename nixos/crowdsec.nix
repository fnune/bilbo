{
  config,
  lib,
  pkgs,
  caddyPublicLogs,
  ...
}: let
  cfg = config.services.crowdsec;
  stateDir = "/var/lib/crowdsec";
  lapiUrl = "http://${cfg.settings.general.api.server.listen_uri}";
  bouncerName = "caddy";
  bouncerEnvDir = "/var/lib/crowdsec-caddy-bouncer";
  bouncerEnv = "${bouncerEnvDir}/env";
  # The module's wrapper points cscli at the generated config; the bare binary looks in /etc.
  cscli = lib.findFirst (p: lib.getName p == "cscli") null config.environment.systemPackages;
in {
  _module.args.crowdsec = {inherit lapiUrl bouncerEnv;};

  services.crowdsec = {
    enable = true;
    autoUpdateService = true;
    hub = {
      collections = ["crowdsecurity/caddy"];
      parsers = ["crowdsecurity/whitelists"];
    };
    localConfig = {
      acquisitions = [
        {
          source = "file";
          filenames = caddyPublicLogs;
          labels.type = "caddy";
        }
      ];
      profiles = [
        {
          name = "default_ip_remediation";
          filters = ["Alert.Remediation == true && Alert.GetScope() == \"Ip\""];
          decisions = [
            {
              type = "ban";
              duration = "4h";
            }
          ];
          on_success = "break";
        }
      ];
    };
    settings = {
      general.api.server.enable = true;
      lapi.credentialsFile = "${stateDir}/lapi-credentials.yaml";
      # Registering with the central API is what pulls the community blocklist.
      capi.credentialsFile = "${stateDir}/capi-credentials.yaml";
    };
  };

  systemd.services.crowdsec.serviceConfig.SupplementaryGroups = [config.services.caddy.group];

  # Caddy only needs the key, so the bouncer registers itself and hands it over in a file.
  systemd.services.crowdsec-caddy-bouncer-register = {
    description = "Register Caddy as a CrowdSec bouncer";
    wantedBy = ["multi-user.target"];
    after = ["crowdsec.service"];
    wants = ["crowdsec.service"];
    before = ["caddy.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = cfg.user;
      Group = cfg.group;
      StateDirectory = "crowdsec-caddy-bouncer";
      UMask = "0077";
    };
    script = ''
      cscli=${lib.getExe cscli}
      if $cscli bouncers list --output json | ${lib.getExe pkgs.jq} -e 'any(.[]; .name == "${bouncerName}")' >/dev/null; then
        [ -s ${bouncerEnv} ] || { echo "Bouncer ${bouncerName} is registered but ${bouncerEnv} is missing; delete it with cscli bouncers delete ${bouncerName}."; exit 1; }
      else
        key=$($cscli bouncers add --output raw -- ${bouncerName})
        echo "CROWDSEC_API_KEY=$key" > ${bouncerEnv}
      fi
    '';
  };
}
