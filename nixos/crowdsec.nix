{
  config,
  lib,
  pkgs,
  caddyPublicLogs,
  ...
}: let
  cfg = config.services.crowdsec;
  stateDir = "/var/lib/crowdsec/state";
  lapiCredentials = "${stateDir}/lapi-credentials.yaml";
  capiCredentials = "${stateDir}/capi-credentials.yaml";
  lapiUrl = "http://${cfg.settings.general.api.server.listen_uri}";
  bouncerName = "caddy";
  bouncerEnvDir = "/var/lib/crowdsec-caddy-bouncer";
  bouncerEnv = "${bouncerEnvDir}/env";
  caddyNeedsRestart = "${bouncerEnvDir}/caddy-needs-restart";
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
      lapi.credentialsFile = lapiCredentials;
      # Registering with the central API is what pulls the community blocklist.
      capi.credentialsFile = capiCredentials;
    };
  };

  systemd.services.crowdsec.serviceConfig.SupplementaryGroups = [config.services.caddy.group];

  # cscli refuses to run while the central API credentials file is missing, and
  # registering is what fills it. The local one is the opposite: the setup only
  # creates it when absent, and refuses to overwrite an empty one.
  systemd.tmpfiles.rules = ["f ${capiCredentials} 0600 ${cfg.user} ${cfg.group} -"];
  systemd.services.crowdsec-drop-empty-lapi-credentials = {
    description = "Let CrowdSec recreate empty local API credentials";
    before = ["crowdsec.service"];
    requiredBy = ["crowdsec.service"];
    serviceConfig.Type = "oneshot";
    script = "[ -s ${lapiCredentials} ] || rm -f ${lapiCredentials}";
  };

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
      # CrowdSec can take a while on first start, and Caddy runs without the key until this succeeds.
      Restart = "on-failure";
      RestartSec = 30;
      ExecStartPost = "+${pkgs.writeShellScript "caddy-reload-bouncer-key" ''
        if [ -e ${caddyNeedsRestart} ]; then
          rm ${caddyNeedsRestart}
          ${pkgs.systemd}/bin/systemctl try-restart --no-block caddy.service
        fi
      ''}";
    };
    script = ''
      cscli=${lib.getExe cscli}
      if $cscli bouncers list --output json | ${lib.getExe pkgs.jq} -e 'any(.[]; .name == "${bouncerName}")' >/dev/null; then
        [ -s ${bouncerEnv} ] || { echo "Bouncer ${bouncerName} is registered but ${bouncerEnv} is missing; delete it with cscli bouncers delete ${bouncerName}."; exit 1; }
      else
        key=$($cscli bouncers add --output raw -- ${bouncerName})
        echo "CROWDSEC_API_KEY=$key" > ${bouncerEnv}
        touch ${caddyNeedsRestart}
      fi
    '';
  };
}
