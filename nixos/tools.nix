{
  lib,
  pkgs,
  ...
}: let
  bilboTools = pkgs.python3Packages.buildPythonApplication {
    pname = "bilbo-tools";
    version = "1.0.0";
    pyproject = true;
    src = ./tools;
    build-system = [pkgs.python3Packages.setuptools];
    dependencies = with pkgs.python3Packages; [anthropic pydantic pyyaml requests];
    nativeCheckInputs = [pkgs.ruff] ++ (with pkgs.python3Packages; [pytest responses]);
    checkPhase = ''
      ruff check .
      ruff format --check .
      pytest
    '';
    meta.mainProgram = "bilbo-tools";
  };
in {
  _module.args = {
    inherit bilboTools;
    bilboToolsCommand = command: settings: "${lib.getExe bilboTools} ${command} ${pkgs.writeText "${command}.json" (builtins.toJSON settings)}";
  };
}
