pkgs: {
  from ? null,
  to,
  owner,
  group,
}: let
  moveLegacy = pkgs.lib.optionalString (from != null) ''
    if [ -d "${from}" ]; then
      mkdir -p "${to}"
      if [ -n "$(find "${to}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        echo "both ${from} and ${to} have content; refusing to merge them" >&2
        exit 1
      fi
      find "${from}" -mindepth 1 -maxdepth 1 -exec mv -t "${to}" {} +
      rmdir "${from}"
    fi
  '';
  script = pkgs.writeShellScript "migrate-state-${owner}" ''
    set -euo pipefail
    ${moveLegacy}
    if [ -d "${to}" ]; then
      chown -R ${owner}:${group} "${to}"
    fi
  '';
in "+${script}"
