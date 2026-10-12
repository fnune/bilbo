{
  bilboTools,
  config,
  lib,
  pkgs,
  ...
}: {
  _module.args.mkSettingsService = {
    name,
    description,
    after,
    settings,
    app ? lib.removeSuffix "-settings" name,
    softAfter ? [],
    restartTriggers ? [],
    secrets ? [],
    serviceConfig ? {},
  }: let
    units = map (service: "${service}.service") after;
    settingsFile = pkgs.writeText "${name}.json" (builtins.toJSON settings);
  in {
    inherit description;
    wantedBy = ["multi-user.target"];
    after = units ++ map (service: "${service}.service") softAfter;
    requires = units;
    restartTriggers = [bilboTools settingsFile] ++ restartTriggers;
    serviceConfig =
      {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe bilboTools} ${app} ${settingsFile}";
        LoadCredential = map (secret: "${secret}:${config.sops.secrets.${secret}.path}") secrets;
      }
      // serviceConfig;
  };
}
