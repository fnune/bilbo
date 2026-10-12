{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.services) radarr sonarr seerr;
  arrUrl = arr: "http://127.0.0.1:${toString arr.settings.server.port}${arr.settings.server.urlbase}/api/v3";
  ntfyUrl = "http://${config.services.ntfy-sh.settings.listen-http}";
  ntfyTopic = "bilbo";
  nzbgetConf = "/var/lib/nzbget/nzbget.conf";
  nzbgetPort = 6789;

  apps = {
    radarr = {
      url = arrUrl radarr;
      rootFolder = "/mnt/downloads-1t/Movies";
      category = {
        field = "movieCategory";
        value = "Movies";
      };
    };
    sonarr = {
      url = arrUrl sonarr;
      rootFolder = "/mnt/downloads-2t/Series";
      category = {
        field = "tvCategory";
        value = "Series";
      };
    };
  };
  # Seerr's default for new requests; left alone until Recyclarr has created it.
  seerrProfile = "1080p, then 720p";

  applySettings = pkgs.writeShellApplication {
    name = "arr-apply-settings";
    runtimeInputs = with pkgs; [curl jq gnugrep];
    text = ''
      call() { # key url [curl args...]
        local key=$1 url=$2
        shift 2
        curl --silent --show-error --fail --header "X-Api-Key: $key" --header "Content-Type: application/json" "$@" "$url"
      }
      wait_for() { # key url
        for _ in $(seq 60); do
          call "$1" "$2" >/dev/null 2>&1 && return 0
          sleep 2
        done
        return 1
      }

      # NZBGet's login lives only in its own config file.
      nzbgetUser=$(grep -oP '^ControlUsername=\K.*' ${nzbgetConf})
      nzbgetPassword=$(grep -oP '^ControlPassword=\K.*' ${nzbgetConf})

      ${lib.concatStrings (lib.mapAttrsToList (name: app: ''
          key=$(cat "$CREDENTIALS_DIRECTORY/${name}-api-key")
          wait_for "$key" ${app.url}/system/status

          if ! call "$key" ${app.url}/rootfolder | jq -e 'any(.[]; .path == "${app.rootFolder}")' >/dev/null; then
            jq -n '{path: "${app.rootFolder}"}' | call "$key" ${app.url}/rootfolder --request POST --data @-
          fi

          if ! call "$key" ${app.url}/downloadclient | jq -e 'any(.[]; .implementation == "Nzbget")' >/dev/null; then
            call "$key" ${app.url}/downloadclient/schema |
              jq --arg user "$nzbgetUser" --arg password "$nzbgetPassword" '
                .[] | select(.implementation == "Nzbget")
                | .name = "NZBGet" | .enable = true
                | .removeCompletedDownloads = true | .removeFailedDownloads = true
                | .fields |= map(
                    if .name == "host" then .value = "127.0.0.1"
                    elif .name == "port" then .value = ${toString nzbgetPort}
                    elif .name == "username" then .value = $user
                    elif .name == "password" then .value = $password
                    elif .name == "${app.category.field}" then .value = "${app.category.value}"
                    else . end)' |
              call "$key" ${app.url}/downloadclient --request POST --data @-
          fi

          # The quality profile's repack scores decide, as TRaSH recommends.
          call "$key" ${app.url}/config/mediamanagement |
            jq -c 'select(.downloadPropersAndRepacks != "doNotPrefer") | .downloadPropersAndRepacks = "doNotPrefer"' |
            while read -r config; do
              call "$key" "${app.url}/config/mediamanagement/$(jq -r .id <<<"$config")" --request PUT --data "$config"
            done

          if ! call "$key" ${app.url}/notification | jq -e 'any(.[]; .implementation == "Ntfy")' >/dev/null; then
            call "$key" ${app.url}/notification/schema |
              jq '
                .[] | select(.implementation == "Ntfy")
                | .name = "ntfy" | .onGrab = true | .onDownload = true | .onUpgrade = true | .onHealthIssue = true
                | .fields |= map(
                    if .name == "serverUrl" then .value = "${ntfyUrl}"
                    elif .name == "topics" then .value = ["${ntfyTopic}"]
                    else . end)' |
              call "$key" ${app.url}/notification --request POST --data @-
          fi
        '')
        apps)}

      seerrKey=$(jq -r .main.apiKey ${seerr.configDir}/settings.json)
      seerr=http://127.0.0.1:${toString seerr.port}/api/v1
      wait_for "$seerrKey" "$seerr/settings/main"
      for app in radarr sonarr; do
        key=$(cat "$CREDENTIALS_DIRECTORY/$app-api-key")
        url=$([ "$app" = radarr ] && echo ${apps.radarr.url} || echo ${apps.sonarr.url})
        profileId=$(call "$key" "$url/qualityprofile" | jq -r '.[] | select(.name == "${seerrProfile}") | .id')
        [ -n "$profileId" ] || continue
        call "$seerrKey" "$seerr/settings/$app" | jq -c --argjson id "$profileId" '.[] | select(.isDefault and .activeProfileId != $id) | .activeProfileId = $id | .activeProfileName = "${seerrProfile}"' |
          while read -r server; do
            call "$seerrKey" "$seerr/settings/$app/$(jq -r .id <<<"$server")" --request PUT --data "$server"
          done
      done
    '';
  };
in {
  systemd.services.arr-settings = {
    description = "Apply Radarr, Sonarr and Seerr settings from this repository";
    wantedBy = ["multi-user.target"];
    after = ["radarr.service" "sonarr.service" "seerr.service" "nzbget.service" "ntfy-sh.service"];
    wants = ["radarr.service" "sonarr.service" "seerr.service"];
    restartTriggers = [applySettings];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe applySettings;
      LoadCredential = [
        "radarr-api-key:${config.sops.secrets.radarr-api-key.path}"
        "sonarr-api-key:${config.sops.secrets.sonarr-api-key.path}"
      ];
    };
  };
}
