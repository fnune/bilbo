{
  pkgs,
  vault,
  basePath,
}: let
  python = pkgs.python3.withPackages (ps: [ps.markdown ps.pyyaml]);
in
  pkgs.runCommand "lists-site" {} ''
    ${python}/bin/python ${./render.py} ${vault} $out --base ${basePath} --assets ${./assets}
  ''
