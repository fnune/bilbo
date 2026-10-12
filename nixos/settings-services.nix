{
  config,
  lib,
  pkgs,
  ...
}: let
  bilboSettings = pkgs.python3Packages.buildPythonApplication {
    pname = "bilbo-settings";
    version = "1.0.0";
    pyproject = true;
    src = ./settings;
    build-system = [pkgs.python3Packages.setuptools];
    dependencies = with pkgs.python3Packages; [pyyaml requests];
    nativeCheckInputs = [pkgs.ruff] ++ (with pkgs.python3Packages; [pytest responses]);
    checkPhase = ''
      ruff check .
      ruff format --check .
      pytest
    '';
    meta.mainProgram = "bilbo-settings";
  };
in {
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
    restartTriggers = [bilboSettings settingsFile] ++ restartTriggers;
    serviceConfig =
      {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe bilboSettings} ${app} ${settingsFile}";
        LoadCredential = map (secret: "${secret}:${config.sops.secrets.${secret}.path}") secrets;
      }
      // serviceConfig;
  };
}
