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
      rootFolder = "/mnt/downloads-1t/Movies";
      categoryField = "movieCategory";
      category = "Movies";
    };
    sonarr = {
      rootFolder = "/mnt/downloads-2t/Series";
      categoryField = "tvCategory";
      category = "Series";
    };
  };

  ntfy = {
    url = "http://${config.services.ntfy-sh.settings.listen-http}";
    topic = "bilbo";
  };
  nzbget = {
    conf = "/var/lib/nzbget/nzbget.conf";
    port = 6789;
  };

  seerrProfile = "1080p, then 720p";
  seerrMain = {
    applicationUrl = "https://requests.fnune.com";
    localLogin = false;
  };

  arrClient = name: ''
    ${name}() {
      local path=$1
      shift
      curl --silent --show-error --fail --header "X-Api-Key: $(credential ${name}-api-key)" \
        --header "Content-Type: application/json" "$@" "${servarrUrl name}/api/v3$path"
    }
  '';

  arrSettings = name: arr: ''
    wait_until_up ${servarrUrl name}/ping

    if missing ${name} /rootfolder '.path == "${arr.rootFolder}"'; then
      jq -n '{path: "${arr.rootFolder}"}' | ${name} /rootfolder --request POST --data @-
    fi

    if missing ${name} /downloadclient '.implementation == "Nzbget"'; then
      ${name} /downloadclient/schema |
        jq --arg user "$nzbgetUser" --arg password "$nzbgetPassword" '
          .[] | select(.implementation == "Nzbget")
          | .name = "NZBGet" | .enable = true
          | .removeCompletedDownloads = true | .removeFailedDownloads = true
          | .fields |= map(
              if .name == "host" then .value = "127.0.0.1"
              elif .name == "port" then .value = ${toString nzbget.port}
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
          seerr "/settings/${name}/$(jq -r .id <<<"$server")" --request PUT --data "$server"
        done
    fi
  '';
in {
  systemd.services.arr-settings = mkSettingsService {
    name = "arr-settings";
    description = "Apply Radarr, Sonarr and Seerr settings from this repository";
    after = ["radarr" "sonarr" "seerr" "nzbget" "ntfy-sh"];
    secrets = ["radarr-api-key" "sonarr-api-key"];
    text = ''
      ${lib.concatStrings (lib.mapAttrsToList (name: _: arrClient name) arrs)}

      seerr() {
        local path=$1
        shift
        curl --silent --show-error --fail --header "X-Api-Key: $(jq -r .main.apiKey ${seerr.configDir}/settings.json)" \
          --header "Content-Type: application/json" "$@" "http://127.0.0.1:${toString seerr.port}/api/v1$path"
      }

      missing() {
        ! "$1" "$2" | jq -e "any(.[]; $3)" >/dev/null
      }

      nzbgetUser=$(sed -n 's/^ControlUsername=//p' ${nzbget.conf})
      nzbgetPassword=$(sed -n 's/^ControlPassword=//p' ${nzbget.conf})

      wait_until_up http://127.0.0.1:${toString seerr.port}/api/v1/status
      seerr /settings/main | jq -c '. * ${builtins.toJSON seerrMain}' |
        seerr /settings/main --request POST --data @- >/dev/null

      ${lib.concatStrings (lib.mapAttrsToList arrSettings arrs)}
    '';
  };
}
