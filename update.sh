#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$repo"

usage() {
  cat <<'USAGE'
usage: ./update.sh [--diff-only] [--since REV] [--no-commit]

  --diff-only  skip `nix flake update`, compare flake.lock against a git rev
  --since REV  the rev --diff-only compares against (default HEAD)
  --no-commit  leave flake.lock in the working tree instead of committing it
USAGE
}

diff_only=false
since=HEAD
commit=true
while [[ $# -gt 0 ]]; do
  arg=$1
  shift
  case "$arg" in
    --diff-only) diff_only=true ;;
    --no-commit) commit=false ;;
    --since)
      since=$1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if $diff_only; then
  commit=false
  git show "$since:flake.lock" >"$work/old.lock"
else
  cp flake.lock "$work/old.lock"
  nix flake update
fi

if cmp -s "$work/old.lock" flake.lock; then
  echo "No input changed."
  exit 0
fi

attr=".#nixosConfigurations.bilbo"

echo "Evaluating package versions..."
apply=$(cat "$repo/lib/versions.nix")
nix eval --json --apply "$apply" --no-write-lock-file --reference-lock-file "$work/old.lock" "$attr" >"$work/old.json"
nix eval --json --apply "$apply" "$attr" >"$work/new.json"

report=$(jq -r -s -f "$repo/lib/report.jq" "$work/old.json" "$work/new.json")

echo
echo "$report"

if $commit; then
  printf 'Upgrade packages\n\n%s\n' "$report" | git commit --only --quiet --file - flake.lock
  echo
  git --no-pager log -1 --oneline
fi
