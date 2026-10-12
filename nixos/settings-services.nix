{
  config,
  lib,
  pkgs,
  ...
}: {
  _module.args.mkSettingsService = {
    name,
    description,
    after,
    softAfter ? [],
    restartTriggers ? [],
    secrets ? [],
    runtimeInputs ? [],
    serviceConfig ? {},
    text,
  }: let
    script = pkgs.writeShellApplication {
      name = "${name}-apply";
      runtimeInputs = [pkgs.curl pkgs.jq] ++ runtimeInputs;
      text =
        ''
          credential() { cat "$CREDENTIALS_DIRECTORY/$1"; }

          wait_until_up() {
            local status
            for _ in $(seq 60); do
              status=$(curl --silent --output /dev/null --write-out '%{http_code}' "$1" || true)
              [ "$status" != 000 ] && [ "$status" -lt 500 ] && return 0
              sleep 2
            done
            echo "$1 did not answer within two minutes" >&2
            return 1
          }

        ''
        + text;
    };
    units = map (service: "${service}.service") after;
  in {
    inherit description;
    wantedBy = ["multi-user.target"];
    after = units ++ map (service: "${service}.service") softAfter;
    requires = units;
    restartTriggers = [script] ++ restartTriggers;
    serviceConfig =
      {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe script;
        LoadCredential = map (secret: "${secret}:${config.sops.secrets.${secret}.path}") secrets;
      }
      // serviceConfig;
  };
}
