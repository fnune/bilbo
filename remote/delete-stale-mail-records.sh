#!/usr/bin/env bash
# One-time cleanup of the stale ProtonMail records on fnune.com, superseded by
# the parked-domain records in cloudflare/mail.ts. Run on bilbo, where the
# scoped DNS token lives:
#
#   ssh -t bilbo 'sudo bash -s' < remote/delete-stale-mail-records.sh          # dry run
#   ssh -t bilbo 'sudo APPLY=1 bash -s' < remote/delete-stale-mail-records.sh  # delete
#
# It only ever touches records whose content matches the stale set below; it
# leaves the apex site, www and the google-site-verification record alone.
set -euo pipefail
ZONE_ID=ae60391afa829b4b5f0e664484989d6b
TOKEN=$(cat /run/secrets/cloudflare-dns-token)
api() { curl -sf -H "Authorization: Bearer $TOKEN" "$@"; }

matches_stale() {
  local type="$1" name="$2" content="$3"
  case "$type:$name" in
    MX:fnune.com) [[ "$content" == *protonmail.ch ]] ;;
    CNAME:protonmail*._domainkey.fnune.com) true ;;
    TXT:fnune.com)
      [[ "$content" == *protonmail* || "$content" == *raiolanetworks* || "$content" == protonmail-verification=* ]] ;;
    *) false ;;
  esac
}

records=$(api "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=100")
echo "$records" | jq -c '.result[] | {id, type, name, content}' | while read -r row; do
  id=$(jq -r .id <<<"$row"); type=$(jq -r .type <<<"$row")
  name=$(jq -r .name <<<"$row"); content=$(jq -r .content <<<"$row")
  if matches_stale "$type" "$name" "$content"; then
    if [ "${APPLY:-0}" = 1 ]; then
      api -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$id" >/dev/null
      echo "deleted  $type $name  $content"
    else
      echo "would delete  $type $name  $content"
    fi
  fi
done
echo "done${APPLY:+ (applied)}"
