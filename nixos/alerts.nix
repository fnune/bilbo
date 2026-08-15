{
  config,
  lib,
  pkgs,
  ...
}: let
  stateDirectory = "/var/lib/bilbo-alerts";

  mqttBroker = builtins.head config.services.mosquitto.listeners;
  mqttAccount = "bilbo-alerts";
  mqttPasswordFile = "/etc/nixos/secrets/mosquitto-${mqttAccount}-password";

  frigateApi = "http://127.0.0.1:8971/api";
  frigateUser = "admin";
  frigatePasswordFile = "/etc/nixos/secrets/frigate-admin-password";
  cameraName = builtins.head (builtins.attrNames config.services.frigate.settings.cameras);

  borgJob = "borgbackup-job-mirrored.service";
  borgRepository = "/mnt/downloads-2t/Backups/borg/mirrored";
  borgPassphraseFile = "/etc/nixos/secrets/borg-passphrase";
  offsiteFailureMarker = "${stateDirectory}/offsite-failed";

  homeAssistantUrl = "http://127.0.0.1:8123/";

  watchedMounts = ["/" "/mnt/downloads-1t" "/mnt/downloads-2t" "/mnt/mirrored"];

  watchedUnits = [
    "bazarr"
    "caddy"
    "calibre-web"
    "filebrowser"
    "grafana"
    "immich-server"
    "jellyfin"
    "mosquitto"
    "nzbget"
    "postgresql"
    "prometheus"
    "radarr"
    "sonarr"
    "zigbee2mqtt"
  ];

  arrs = [
    {
      name = "Sonarr";
      url = "http://127.0.0.1:8989/sonarr";
      configFile = "${config.users.users.fausto.home}/sonarr/config.xml";
    }
    {
      name = "Radarr";
      url = "http://127.0.0.1:7878/radarr";
      configFile = "${config.users.users.fausto.home}/radarr/config.xml";
    }
  ];

  subscribe = ''
    mqtt_read() {
      mosquitto_sub \
        -h ${mqttBroker.address} -p ${toString mqttBroker.port} \
        -u ${mqttAccount} -P "$(cat ${mqttPasswordFile})" \
        -t "$1" -C 1 -W 3 2>/dev/null || true
    }

    mqtt_read_all() {
      mosquitto_sub \
        -h ${mqttBroker.address} -p ${toString mqttBroker.port} \
        -u ${mqttAccount} -P "$(cat ${mqttPasswordFile})" \
        -t "$1" -v -W 3 2>/dev/null || true
    }
  '';

  frigateSession = ''
    session="$(mktemp)"
    trap 'rm -f "$session"' EXIT

    frigate_login() {
      curl --silent --fail --max-time 10 --cookie-jar "$session" \
        --request POST "${frigateApi}/login" \
        --header "Content-Type: application/json" \
        --data "$(jq --null-input --compact-output \
          --arg user "${frigateUser}" \
          --arg password "$(cat ${frigatePasswordFile})" \
          "{user: \$user, password: \$password}")" \
        > /dev/null
    }

    frigate_fetch() {
      curl --silent --fail --max-time 10 --cookie "$session" "${frigateApi}/$1"
    }
  '';

  borgRead = ''
    borg_read() {
      BORG_PASSCOMMAND="cat ${borgPassphraseFile}" \
        borg "$@" --json --lock-wait 0 ${borgRepository} 2>/dev/null || true
    }
  '';

  diskUsage = ''
    disk_usage() {
      local used
      used="$(df --output=pcent "$1" | tail -n 1 | tr -cd '0-9' || true)"
      printf '%s' "''${used:-0}"
    }

    disk_label() {
      local label="''${1##*/}"
      printf '%s' "''${label:-root}"
    }
  '';

  evaluate = pkgs.writeShellApplication {
    name = "bilbo-alerts";
    runtimeInputs = [
      config.bilbo.notify
      pkgs.borgbackup
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
      pkgs.mosquitto
      pkgs.systemd
    ];
    text = ''
      state_dir="${stateDirectory}"
      now="$(date +%s)"

      install --directory --mode 0700 "$state_dir"

      ${subscribe}
      ${frigateSession}
      ${borgRead}
      ${diskUsage}

      raise() {
        local key="$1" topic="$2" schedule="$3" title="$4" body="$5"
        local state="$state_dir/$key"
        local first_seen stage waited due priority index step
        local steps=()

        if [ ! -f "$state" ]; then
          printf '%s 0\n' "$now" > "$state"
        fi

        read -r first_seen stage < "$state"
        waited=$(( (now - first_seen) / 60 ))

        due=0
        index=0
        priority="default"
        IFS=',' read -r -a steps <<< "$schedule"

        for step in "''${steps[@]}"; do
          index=$(( index + 1 ))
          if [ "$waited" -ge "''${step%%:*}" ]; then
            due="$index"
            priority="''${step##*:}"
          fi
        done

        if [ "$due" -gt "$stage" ]; then
          bilbo-notify --topic "$topic" --priority "$priority" --title "$title" --body "$body"
          printf '%s %s\n' "$first_seen" "$due" > "$state"
        fi
      }

      resolve() {
        local key="$1" topic="$2" title="$3"
        local state="$state_dir/$key"
        local stage

        if [ ! -f "$state" ]; then
          return 0
        fi

        read -r _ stage < "$state"
        rm -f "$state"

        if [ "$stage" -gt 0 ]; then
          bilbo-notify --topic "$topic" --priority low --title "$title" --body "Back to normal."
        fi
      }

      camera_is_armed() {
        [ "$(mqtt_read "frigate/${cameraName}/enabled/state")" = "ON" ]
      }

      check_mirror() {
        local title="Storage · mirror degraded"
        local health

        health="$(grep -oE '\[[U_]+\]' /proc/mdstat | head -n 1 || true)"

        if [ -z "$health" ] || [ "''${health//_/}" = "$health" ]; then
          resolve mirror-degraded hardware "$title"
          return 0
        fi

        raise mirror-degraded hardware "0:urgent" "$title" \
          "The array reads $health. Everything is still there, but a second failure now loses it.
Replace the disk, then follow 'Replacing a mirror disk' in the Bilbo README."
      }

      check_surveillance() {
        local title="Camera · surveillance stopped"
        local problem="" frames=""

        if ! camera_is_armed; then
          resolve camera-dark surveillance "$title"
          return 0
        fi

        if ! systemctl is-active --quiet frigate.service; then
          problem="Frigate is not running"
        elif ! systemctl is-active --quiet go2rtc.service; then
          problem="go2rtc is not running"
        elif ! frigate_login; then
          problem="Frigate is not answering"
        else
          frames="$(frigate_fetch stats | jq -r '(.cameras."${cameraName}".camera_fps // 0) | floor' || true)"
          case "$frames" in
            "" | *[!0-9]*) frames=0 ;;
          esac
          if [ "$frames" -lt 1 ]; then
            problem="no frames are arriving from the camera"
          fi
        fi

        if [ -z "$problem" ]; then
          resolve camera-dark surveillance "$title"
          return 0
        fi

        raise camera-dark surveillance "5:urgent" "$title" \
          "The camera is armed and $problem.
Restart go2rtc first. If that does not fix it the camera itself is unreachable."
      }

      check_home_assistant() {
        local title="Camera · Home Assistant unreachable"
        local code

        code="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' ${homeAssistantUrl} || true)"

        if [ -n "$code" ] && [ "$code" != "000" ]; then
          resolve home-assistant-down surveillance "$title"
          return 0
        fi

        if camera_is_armed; then
          raise home-assistant-down surveillance "10:high" "$title" \
            "The camera is armed and Home Assistant is not answering, so it will not disarm or run the lights.
Check systemctl status home-assistant."
        else
          raise home-assistant-down infra "30:default" "$title" \
            "The camera will not arm itself when you next leave."
        fi
      }

      check_units() {
        local unit title

        for unit in ${lib.concatStringsSep " " watchedUnits}; do
          title="Infra · $unit failed"

          if [ "$(systemctl is-failed "$unit.service" || true)" = "failed" ]; then
            raise "unit-$unit" infra "30:default,360:high" "$title" \
              "$(journalctl --unit "$unit.service" --lines 3 --no-pager --output cat || true)"
          else
            resolve "unit-$unit" infra "$title"
          fi
        done
      }

      check_backup() {
        local failed_title="Infra · backup failed"
        local overdue_title="Infra · backup overdue"
        local archived archived_at age

        if [ "$(systemctl is-failed ${borgJob} || true)" = "failed" ]; then
          raise backup-failed infra "0:default" "$failed_title" \
            "$(journalctl --unit ${borgJob} --lines 3 --no-pager --output cat || true)"
        else
          resolve backup-failed infra "$failed_title"
        fi

        archived="$(borg_read list --last 1 | jq -r '.archives[0].time // empty' || true)"
        archived_at="$(date --date "$archived" +%s 2>/dev/null || true)"

        if [ -z "$archived_at" ]; then
          return 0
        fi

        age=$(( (now - archived_at) / 86400 ))

        if [ "$age" -ge 10 ]; then
          raise backup-overdue infra "0:default" "$overdue_title" "The newest archive is $age days old."
        else
          resolve backup-overdue infra "$overdue_title"
        fi
      }

      check_offsite() {
        local title="Infra · off-site copy behind"

        if [ -f "${offsiteFailureMarker}" ]; then
          raise offsite-behind infra "10080:default,40320:high" "$title" \
            "The local Borg archive is current. Only the copy in S3 is behind."
        else
          resolve offsite-behind infra "$title"
        fi
      }

      check_disks() {
        local mount label used title

        for mount in ${lib.concatStringsSep " " watchedMounts}; do
          label="$(disk_label "$mount")"
          used="$(disk_usage "$mount")"
          title="Infra · $label at $used percent"

          if [ "$used" -ge 90 ]; then
            raise "disk-$label" infra "1440:default,4320:high" "$title" \
              "$(df --output=avail --human-readable "$mount" | tail -n 1 | tr -d ' ') free."
          else
            resolve "disk-$label" infra "$title"
          fi
        done
      }

      check_zigbee() {
        local bridge_title="Infra · Zigbee2MQTT offline"
        local bridge line topic payload name key device_title

        bridge="$(mqtt_read 'zigbee2mqtt/bridge/state')"

        if printf '%s' "$bridge" | grep -q offline; then
          raise zigbee-bridge infra "30:default" "$bridge_title" \
            "Nothing Zigbee answers while this is down."
        else
          resolve zigbee-bridge infra "$bridge_title"
        fi

        while IFS= read -r line; do
          if [ -z "$line" ]; then
            continue
          fi

          topic="''${line% *}"
          payload="''${line##* }"
          name="''${topic#zigbee2mqtt/}"
          name="''${name%/availability}"

          if [ "$name" = "bridge" ]; then
            continue
          fi

          key="zigbee-$(printf '%s' "$name" | tr -c 'a-zA-Z0-9' '-')"
          device_title="Infra · $name offline"

          if printf '%s' "$payload" | grep -q offline; then
            raise "$key" infra "15:default" "$device_title" "Zigbee2MQTT has not heard from it."
          else
            resolve "$key" infra "$device_title"
          fi
        done <<< "$(mqtt_read_all 'zigbee2mqtt/+/availability')"
      }

      check_restart() {
        local current previous clean

        current="$(cat /proc/sys/kernel/random/boot_id)"
        previous="$(cat "$state_dir/boot-id" 2>/dev/null || true)"
        clean="$(cat "$state_dir/last-clean-boot" 2>/dev/null || true)"

        printf '%s\n' "$current" > "$state_dir/boot-id"

        if [ -z "$previous" ] || [ "$previous" = "$current" ] || [ "$clean" = "$previous" ]; then
          return 0
        fi

        bilbo-notify --topic infra --priority low --title "Infra · Bilbo restarted" \
          --body "The last shutdown was not clean, which usually means the power went out."
      }

      check_mirror
      check_surveillance
      check_home_assistant
      check_units
      check_backup
      check_offsite
      check_disks
      check_zigbee
      check_restart
    '';
  };

  digest = pkgs.writeShellApplication {
    name = "bilbo-digest";
    runtimeInputs = [
      config.bilbo.notify
      pkgs.borgbackup
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      ${frigateSession}
      ${borgRead}
      ${diskUsage}

      report="$(mktemp)"
      trap 'rm -f "$session" "$report"' EXIT

      since="$(date --date '7 days ago' --iso-8601=seconds)"

      summarise_arr() {
        local name="$1" url="$2" config_file="$3"
        local key grabs problems

        key="$(grep -o '<ApiKey>[^<]*' "$config_file" | cut -d '>' -f 2 || true)"

        if [ -z "$key" ]; then
          return 0
        fi

        grabs="$(curl --silent --fail --max-time 15 --header "X-Api-Key: $key" \
          "$url/api/v3/history/since?date=$since&eventType=grabbed" | jq 'length' || true)"

        printf '%s grabbed %s\n' "$name" "''${grabs:-0}"

        problems="$(curl --silent --fail --max-time 15 --header "X-Api-Key: $key" \
          "$url/api/v3/health" | jq -r '.[] | select(.type != "ok") | "  " + .message' || true)"

        if [ -n "$problems" ]; then
          printf '%s\n' "$problems"
        fi
      }

      summarise_backup() {
        local size archived archived_at

        size="$(borg_read info | jq -r '.cache.stats.unique_csize // empty' || true)"
        archived="$(borg_read list --last 1 | jq -r '.archives[0].time // empty' || true)"
        archived_at="$(date --date "$archived" +%s 2>/dev/null || true)"

        if [ -z "$archived_at" ]; then
          printf 'Backup unreadable\n'
          return 0
        fi

        printf 'Backup %s, newest archive %s days old\n' \
          "$(numfmt --to=iec --suffix=B "''${size:-0}")" \
          "$(( ($(date +%s) - archived_at) / 86400 ))"
      }

      summarise_disks() {
        local mount

        printf 'Disks'
        for mount in ${lib.concatStringsSep " " watchedMounts}; do
          printf ' %s %s%%' "$(disk_label "$mount")" "$(disk_usage "$mount")"
        done
        printf '\n'
      }

      summarise_camera() {
        local unreviewed=""

        if frigate_login; then
          unreviewed="$(frigate_fetch 'review?reviewed=0&severity=alert&limit=100' | jq 'length' || true)"
        fi

        printf '%s unreviewed camera alerts\n' "''${unreviewed:-0}"
      }

      {
        ${lib.concatMapStringsSep "\n" (arr: ''summarise_arr "${arr.name}" "${arr.url}" "${arr.configFile}"'') arrs}
        summarise_backup
        summarise_disks
        summarise_camera
      } > "$report"

      bilbo-notify --topic digest --priority low --title "Weekly · Bilbo" --body "$(cat "$report")"
    '';
  };

  reportSmartFailure = pkgs.writeShellApplication {
    name = "bilbo-smart-alert";
    runtimeInputs = [config.bilbo.notify];
    text = ''
      bilbo-notify --topic hardware --priority urgent \
        --title "Storage · ''${SMARTD_DEVICESTRING:-a disk} is failing" \
        --body "''${SMARTD_MESSAGE:-SMART reported a problem.}
Replace this disk before it drops out on its own."
    '';
  };

  recordCleanShutdown = pkgs.writeShellApplication {
    name = "bilbo-record-clean-shutdown";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      install --directory --mode 0700 ${stateDirectory}
      cat /proc/sys/kernel/random/boot_id > ${stateDirectory}/last-clean-boot
    '';
  };

  forwardHomeAssistant = pkgs.writeShellApplication {
    name = "bilbo-notify-bridge";
    runtimeInputs = [config.bilbo.notify pkgs.jq pkgs.mosquitto];
    text = ''
      mosquitto_sub \
        -h ${mqttBroker.address} -p ${toString mqttBroker.port} \
        -u ${mqttAccount} -P "$(cat ${mqttPasswordFile})" \
        -t 'bilbo/notify' \
        | while read -r message; do
          if ! printf '%s' "$message" | jq -e . > /dev/null 2>&1; then
            continue
          fi

          bilbo-notify \
            --topic "$(printf '%s' "$message" | jq -r '.topic')" \
            --priority "$(printf '%s' "$message" | jq -r '.priority // "default"')" \
            --title "$(printf '%s' "$message" | jq -r '.title')" \
            --body "$(printf '%s' "$message" | jq -r '.body')"
        done
    '';
  };
in {
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.monitored = "-a -o on -s (S/../.././02|L/../../6/03) -m <nomailer> -M exec ${lib.getExe reportSmartFailure}";
  };

  systemd.tmpfiles.settings."10-bilbo-alerts"."${stateDirectory}".d = {
    user = "root";
    group = "root";
    mode = "0700";
  };

  systemd.services = {
    bilbo-alerts = {
      description = "Look for anything on Bilbo worth a notification";
      startAt = "*:0/2";
      after = ["network-online.target" "ntfy-sh.service"];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = 120;
        ExecStart = lib.getExe evaluate;
      };
    };

    bilbo-digest = {
      description = "Send the weekly summary";
      startAt = "Mon 09:00";
      after = ["network-online.target" "ntfy-sh.service"];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = 300;
        ExecStart = lib.getExe digest;
      };
    };

    bilbo-notify-bridge = {
      description = "Pass Home Assistant notifications on to the phone";
      wantedBy = ["multi-user.target"];
      after = ["mosquitto.service" "ntfy-sh.service"];
      serviceConfig = {
        ExecStart = lib.getExe forwardHomeAssistant;
        Restart = "always";
        RestartSec = 10;
      };
    };

    bilbo-shutdown-marker = {
      description = "Remember that Bilbo was shut down on purpose";
      wantedBy = ["multi-user.target"];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = lib.getExe recordCleanShutdown;
      };
    };
  };
}
