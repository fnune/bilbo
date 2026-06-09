#!/usr/bin/env bash
# Pre-flight checks before deploying the NixOS 26.05 upgrade on bilbo.
# Run as root on the server BEFORE `nixos-rebuild switch`:
#   sudo ./preflight-2605.sh
#
# It does the safe, automatic steps (Jellyfin backup, file checks) and reports
# on the Immich vector extension. It will NOT drop anything destructive on its
# own; if action is needed it prints the exact command for you to run.

set -euo pipefail

BACKUP_DIR="${1:-/var/backup}"
STAMP="$(date +%F-%H%M%S)"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  red "Must run as root (sudo ./preflight-2605.sh)"; exit 1
fi

needs_attention=0

# ---------------------------------------------------------------------------
bold "[1/3] Immich: check for the old pgvecto.rs 'vectors' extension"
# 26.05 removed pgvecto.rs; VectorChord (vchord) is now mandatory.
if ! systemctl is-active --quiet postgresql; then
  yellow "  postgresql is not running; starting it for the check..."
  systemctl start postgresql
fi

dx="$(runuser -u postgres -- psql -tAc '\dx' immich 2>/dev/null || true)"
if [[ -z "$dx" ]]; then
  yellow "  Could not read extensions from the 'immich' database (does it exist yet?). Skipping."
else
  echo "  Installed extensions:"
  echo "$dx" | sed 's/^/    /'
  if echo "$dx" | grep -qiw 'vectors'; then
    red   "  >> The legacy 'vectors' (pgvecto.rs) extension is STILL PRESENT."
    red   "  >> Do NOT upgrade to 26.05 yet. First let VectorChord finish migrating"
    red   "     on the current (25.11) system, then drop the old extension:"
    echo
    echo  "       sudo -u postgres psql immich -c 'DROP EXTENSION vectors;'"
    echo  "       sudo -u postgres psql immich -c 'DROP SCHEMA vectors;'"
    echo
    red   "  >> This is irreversible - dump the DB first if you want a rollback."
    needs_attention=1
  elif echo "$dx" | grep -qiw 'vchord'; then
    green "  OK: VectorChord (vchord) present, no legacy 'vectors' extension. Safe to upgrade."
  else
    yellow "  Neither 'vectors' nor 'vchord' found - verify Immich's DB state manually."
  fi
fi
echo

# ---------------------------------------------------------------------------
bold "[2/3] Jellyfin: back up /var/lib/jellyfin (10.11 runs a one-way DB migration)"
if [[ -d /var/lib/jellyfin ]]; then
  mkdir -p "$BACKUP_DIR"
  archive="$BACKUP_DIR/jellyfin-$STAMP.tar.zst"
  was_active=0
  if systemctl is-active --quiet jellyfin; then was_active=1; fi
  echo "  Stopping jellyfin for a consistent backup..."
  systemctl stop jellyfin || true
  echo "  Writing $archive ..."
  tar --zstd -cf "$archive" -C /var/lib jellyfin
  if [[ $was_active -eq 1 ]]; then
    echo "  Restarting jellyfin..."
    systemctl start jellyfin
  fi
  green "  OK: backup written to $archive ($(du -h "$archive" | cut -f1))"
else
  yellow "  /var/lib/jellyfin not found; skipping."
fi
echo

# ---------------------------------------------------------------------------
bold "[3/3] Verify required secret files exist"
if [[ -s /etc/grafana/secret-key ]]; then
  green "  OK: /etc/grafana/secret-key exists (26.05 dropped the built-in default)."
else
  red   "  >> /etc/grafana/secret-key is missing or empty. Grafana references it via"
  red   "     \$__file{...} and 26.05 has no default - create it, e.g.:"
  echo  "       openssl rand -base64 32 | sudo tee /etc/grafana/secret-key >/dev/null"
  needs_attention=1
fi

if [[ -s /etc/cloudflare/token ]]; then
  if grep -q 'CLOUDFLARE_API_TOKEN=' /etc/cloudflare/token; then
    red "  >> /etc/cloudflare/token must contain ONLY the bare token, not a"
    red "     'CLOUDFLARE_API_TOKEN=...' assignment. Fix it before deploying."
    needs_attention=1
  else
    green "  OK: /etc/cloudflare/token exists and looks like a bare token."
  fi
else
  red "  >> /etc/cloudflare/token is missing or empty."
  needs_attention=1
fi
echo

# ---------------------------------------------------------------------------
if [[ $needs_attention -eq 0 ]]; then
  green "All checks passed. You can proceed:"
  echo  "  sudo nixos-rebuild switch --flake .#bilbo && sudo reboot"
else
  red   "Some items need attention (see above). Resolve them before deploying."
  exit 2
fi
