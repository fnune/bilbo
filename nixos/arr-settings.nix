{
  config,
  lib,
  libraries,
  mkSettingsService,
  servarrUrl,
  ...
}: let
  inherit (config.services) seerr;

  arrs = {
    radarr = {
      implementation = "Radarr";
      rootFolder = libraries.movies;
      categoryField = "movieCategory";
      category = "Movies";
      seerrServer.minimumAvailability = "released";
    };
    sonarr = {
      implementation = "Sonarr";
      rootFolder = libraries.series;
      categoryField = "tvCategory";
      category = "Series";
      seerrServer.enableSeasonFolders = true;
    };
  };

  ntfy = {
    url = "http://${config.services.ntfy-sh.settings.listen-http}";
    topic = "bilbo";
  };
  nzbgetPort = 6789;
  prowlarrConfig = "/var/lib/private/prowlarr/config.xml";

  seerrProfile = "1080p, then 720p";
  seerrNotConfigured = 4;
  seerrJellyfin = 2;
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
    ensure_login ${name}

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

    if missing seerr /settings/${name} true; then
      ${name} /qualityprofile |
        jq --arg key "$(credential ${name}-api-key)" '
          (map(select(.name == "${seerrProfile}")) + .)[0] as $profile
          | {
              name: "${arr.implementation}", hostname: "127.0.0.1",
              port: ${toString config.services.${name}.settings.server.port},
              baseUrl: "${config.services.${name}.settings.server.urlbase}", useSsl: false, apiKey: $key,
              activeProfileId: $profile.id, activeProfileName: $profile.name, activeDirectory: "${arr.rootFolder}",
              is4k: false, isDefault: true, syncEnabled: true, preventSearch: false, tags: []
            } + ${builtins.toJSON arr.seerrServer}' |
        seerr /settings/${name} --request POST --data @- >/dev/null
    fi

    profileId=$(${name} /qualityprofile | jq '[.[] | select(.name == "${seerrProfile}") | .id] | first')
    seerr /settings/${name} |
      jq -c --argjson profileId "$profileId" '.[] | select(.isDefault) | . as $current
        | .hostname = "127.0.0.1"
        | if $profileId then .activeProfileId = $profileId | .activeProfileName = "${seerrProfile}" else . end
        | select(. != $current)' |
      while read -r server; do
        seerr "/settings/${name}/$(jq -r .id <<<"$server")" --request PUT --data "$(jq -c 'del(.id)' <<<"$server")"
      done
  '';
in {
  sops.secrets = lib.genAttrs ["nzbgeek-api-key" "servarr-username" "servarr-password"] (_: {});

  systemd.services.arr-settings = mkSettingsService {
    name = "arr-settings";
    description = "Apply Radarr, Sonarr, Prowlarr and Seerr settings from this repository";
    after = ["radarr" "sonarr" "prowlarr" "seerr" "nzbget" "ntfy-sh"];
    softAfter = ["recyclarr-on-change" "jellyfin-settings"];
    secrets = ["radarr-api-key" "sonarr-api-key" "nzbget-username" "nzbget-password" "nzbgeek-api-key" "servarr-username" "servarr-password" "jellyfin-admin-username" "jellyfin-admin-password"];
    text = ''
      ${lib.concatStrings (lib.mapAttrsToList (name: _: arrClient name) arrs)}

      seerr() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "X-Api-Key: $(jq -r .main.apiKey ${seerr.configDir}/settings.json)" \
          --header "Content-Type: application/json" "$@" "http://127.0.0.1:${toString seerr.port}/api/v1$path"
      }

      ensure_login() {
        "$1" /config/host |
          jq -c --arg user "$(credential servarr-username)" --arg password "$(credential servarr-password)" '
            select(.username != $user)
            | .username = $user | .password = $password | .passwordConfirmation = $password
            | .authenticationMethod = "forms" | .authenticationRequired = "enabled"' |
          while read -r host; do
            "$1" "/config/host/$(jq -r .id <<<"$host")" --request PUT --data "$host" >/dev/null
          done
      }

      missing() {
        ! "$1" "$2" | jq -e "any(.[]; $3)" >/dev/null
      }


      wait_until_up http://127.0.0.1:${toString seerr.port}/api/v1/status
      seerrPublic() { curl --silent --show-error --fail-with-body "http://127.0.0.1:${toString seerr.port}/api/v1/settings/public"; }

      if seerrPublic | jq -e '.mediaServerType == ${toString seerrNotConfigured}' >/dev/null; then
        jq -n --arg username "$(credential jellyfin-admin-username)" --arg password "$(credential jellyfin-admin-password)" '{
          username: $username, password: $password, serverType: ${toString seerrJellyfin},
          hostname: "127.0.0.1", port: 8096, urlBase: "/jellyfin", useSsl: false
        }' | curl --silent --show-error --fail-with-body --header "Content-Type: application/json" \
          --data @- "http://127.0.0.1:${toString seerr.port}/api/v1/auth/jellyfin" >/dev/null
        libraryIds=$(seerr "/settings/jellyfin/library?sync=true" | jq -r 'map(.id) | join(",")')
        seerr "/settings/jellyfin/library?enable=$libraryIds" >/dev/null
      fi
      seerr /settings/main --request POST --data ${lib.escapeShellArg (builtins.toJSON seerrMain)} >/dev/null

      ${lib.concatStrings (lib.mapAttrsToList arrSettings arrs)}

      if seerrPublic | jq -e '.initialized | not' >/dev/null; then
        seerr /settings/jellyfin/users | jq '{jellyfinUserIds: map(.id)}' |
          seerr /user/import-from-jellyfin --request POST --data @- >/dev/null
        seerr /settings/initialize --request POST >/dev/null
      fi

      prowlarr() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "X-Api-Key: $(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' ${prowlarrConfig})" \
          --header "Content-Type: application/json" "$@" "${servarrUrl "prowlarr"}/api/v1$path"
      }

      wait_until_up ${servarrUrl "prowlarr"}/ping
      ensure_login prowlarr

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
