{
  bilboToolsCommand,
  config,
  lib,
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
    command = bilboToolsCommand app settings;
  in {
    inherit description;
    wantedBy = ["multi-user.target"];
    after = units ++ map (service: "${service}.service") softAfter;
    requires = units;
    restartTriggers = [command] ++ restartTriggers;
    serviceConfig =
      {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = command;
        LoadCredential = map (secret: "${secret}:${config.sops.secrets.${secret}.path}") secrets;
      }
      // serviceConfig;
  };
}
