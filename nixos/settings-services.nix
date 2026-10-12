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
            for _ in $(seq 60); do
              curl --silent --output /dev/null "$1" && return 0
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
    after = units;
    requires = units;
    restartTriggers = [script];
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
