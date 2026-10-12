{
  config,
  lib,
  mkSettingsService,
  servarrUrl,
  ...
}: let
  inherit (config.services) seerr;

  arrs = {
    radarr = {
      implementation = "Radarr";
      rootFolder = "/mnt/downloads-1t/Movies";
      categoryField = "movieCategory";
      category = "Movies";
    };
    sonarr = {
      implementation = "Sonarr";
      rootFolder = "/mnt/downloads-2t/Series";
      categoryField = "tvCategory";
      category = "Series";
    };
  };

  ntfy = {
    url = "http://${config.services.ntfy-sh.settings.listen-http}";
    topic = "bilbo";
  };
  nzbgetPort = 6789;
  prowlarrConfig = "/var/lib/private/prowlarr/config.xml";

  seerrProfile = "1080p, then 720p";
  seerrMain = {
    applicationUrl = "https://requests.fnune.com";
    localLogin = false;
  };

  arrClient = name: ''
    ${name}() {
      local path=$1
      shift
      curl --silent --show-error --fail-with-body --header "X-Api-Key: $(credential ${name}-api-key)" \
        --header "Content-Type: application/json" "$@" "${servarrUrl name}/api/v3$path"
    }
  '';

  prowlarrApp = name: arr: ''
    if missing prowlarr /applications '.implementation == "${arr.implementation}"'; then
      prowlarr /applications/schema |
        jq --arg key "$(credential ${name}-api-key)" '
          .[] | select(.implementation == "${arr.implementation}")
          | .name = "${arr.implementation}" | .syncLevel = "fullSync"
          | .fields |= map(
              if .name == "prowlarrUrl" then .value = "${servarrUrl "prowlarr"}"
              elif .name == "baseUrl" then .value = "${servarrUrl name}"
              elif .name == "apiKey" then .value = $key
              else . end)' |
        prowlarr /applications --request POST --data @- >/dev/null
    fi
  '';

  handAddedIndexer = "NZBgeek";
  dropHandAddedIndexer = name: ''
    if ! missing ${name} /indexer '.name | endswith("(Prowlarr)")'; then
      ${name} /indexer | jq -r '.[] | select(.name == "${handAddedIndexer}") | .id' |
        while read -r id; do
          ${name} "/indexer/$id" --request DELETE
        done
    fi
  '';

  arrSettings = name: arr: ''
    wait_until_up ${servarrUrl name}/ping

    if missing ${name} /rootfolder '.path == "${arr.rootFolder}"'; then
      jq -n '{path: "${arr.rootFolder}"}' | ${name} /rootfolder --request POST --data @-
    fi

    if missing ${name} /downloadclient '.implementation == "Nzbget"'; then
      ${name} /downloadclient/schema |
        jq --arg user "$(credential nzbget-username)" --arg password "$(credential nzbget-password)" '
          .[] | select(.implementation == "Nzbget")
          | .name = "NZBGet" | .enable = true
          | .removeCompletedDownloads = true | .removeFailedDownloads = true
          | .fields |= map(
              if .name == "host" then .value = "127.0.0.1"
              elif .name == "port" then .value = ${toString nzbgetPort}
              elif .name == "username" then .value = $user
              elif .name == "password" then .value = $password
              elif .name == "${arr.categoryField}" then .value = "${arr.category}"
              else . end)' |
        ${name} /downloadclient --request POST --data @-
    fi

    if missing ${name} /notification '.implementation == "Ntfy"'; then
      ${name} /notification/schema |
        jq '
          .[] | select(.implementation == "Ntfy")
          | .name = "ntfy" | .onGrab = true | .onDownload = true | .onUpgrade = true | .onHealthIssue = true
          | .fields |= map(
              if .name == "serverUrl" then .value = "${ntfy.url}"
              elif .name == "topics" then .value = ["${ntfy.topic}"]
              else . end)' |
        ${name} /notification --request POST --data @-
    fi

    ${name} /config/mediamanagement |
      jq -c 'select(.downloadPropersAndRepacks != "doNotPrefer") | .downloadPropersAndRepacks = "doNotPrefer"' |
      while read -r settings; do
        ${name} "/config/mediamanagement/$(jq -r .id <<<"$settings")" --request PUT --data "$settings"
      done

    profileId=$(${name} /qualityprofile | jq -r '.[] | select(.name == "${seerrProfile}") | .id')
    if [ -n "$profileId" ]; then
      seerr /settings/${name} |
        jq -c --argjson id "$profileId" '.[] | select(.isDefault and .activeProfileId != $id)
          | .activeProfileId = $id | .activeProfileName = "${seerrProfile}"' |
        while read -r server; do
          seerr "/settings/${name}/$(jq -r .id <<<"$server")" --request PUT --data "$(jq -c 'del(.id)' <<<"$server")"
        done
    fi
  '';
in {
  sops.secrets.nzbgeek-api-key = {};

  systemd.services.arr-settings = mkSettingsService {
    name = "arr-settings";
    description = "Apply Radarr, Sonarr, Prowlarr and Seerr settings from this repository";
    after = ["radarr" "sonarr" "prowlarr" "seerr" "nzbget" "ntfy-sh"];
    secrets = ["radarr-api-key" "sonarr-api-key" "nzbget-username" "nzbget-password" "nzbgeek-api-key"];
    text = ''
      ${lib.concatStrings (lib.mapAttrsToList (name: _: arrClient name) arrs)}

      seerr() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "X-Api-Key: $(jq -r .main.apiKey ${seerr.configDir}/settings.json)" \
          --header "Content-Type: application/json" "$@" "http://127.0.0.1:${toString seerr.port}/api/v1$path"
      }

      missing() {
        ! "$1" "$2" | jq -e "any(.[]; $3)" >/dev/null
      }


      wait_until_up http://127.0.0.1:${toString seerr.port}/api/v1/status
      seerr /settings/main --request POST --data ${lib.escapeShellArg (builtins.toJSON seerrMain)} >/dev/null

      ${lib.concatStrings (lib.mapAttrsToList arrSettings arrs)}

      prowlarr() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "X-Api-Key: $(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' ${prowlarrConfig})" \
          --header "Content-Type: application/json" "$@" "${servarrUrl "prowlarr"}/api/v1$path"
      }

      wait_until_up ${servarrUrl "prowlarr"}/ping

      if missing prowlarr /indexer '.name == "${handAddedIndexer}"'; then
        prowlarr /indexer/schema |
          jq --arg key "$(credential nzbgeek-api-key)" '
            [.[] | select(.implementation == "Newznab" and (.name | ascii_downcase) == "nzbgeek")]
            | if length == 0 then error("Prowlarr has no NZBgeek indexer definition") else first end
            | .name = "${handAddedIndexer}" | .enable = true | .appProfileId = 1
            | .fields |= map(if .name == "apiKey" then .value = $key else . end)' |
          prowlarr /indexer --request POST --data @- >/dev/null
      fi

      ${lib.concatStrings (lib.mapAttrsToList prowlarrApp arrs)}
      prowlarr /command --request POST --data '{"name": "ApplicationIndexerSync"}' >/dev/null

      ${lib.concatStrings (lib.mapAttrsToList (name: _: dropHandAddedIndexer name) arrs)}
    '';
  };
}
