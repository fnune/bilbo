#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$repo"

usage() {
  cat <<'USAGE'
usage: ./deploy.sh REV ACTION [NIXOS_REBUILD_OPTION...]

  REV     the jj revision to deploy, such as main or @-; @ deploys the working copy
  ACTION  any nixos-rebuild action, such as switch, test or dry-activate

Options after ACTION go to nixos-rebuild unchanged.
USAGE
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi
rev=$1
action=$2
shift 2

commit=$(jj log --no-graph --revisions "exactly($rev, 1)" --template commit_id)
jj log --no-graph --revisions "$commit" --template builtin_log_oneline

bilbo_github_read_token=$(sops --decrypt --extract '["github-read-token"]' secrets/bilbo.yaml)
github_access_for_private_inputs="access-tokens = github.com=$bilbo_github_read_token"
NIX_CONFIG="$github_access_for_private_inputs${NIX_CONFIG:+$'\n'$NIX_CONFIG}"
export NIX_CONFIG

nixos_rebuild_pinned_to_bilbo=(nix run --inputs-from . nixpkgs#nixos-rebuild-ng --)

"${nixos_rebuild_pinned_to_bilbo[@]}" "$action" \
  --flake "git+file://$repo?ref=HEAD&rev=$commit#bilbo" \
  --target-host bilbo \
  --build-host bilbo \
  --sudo --ask-sudo-password \
  "$@"
