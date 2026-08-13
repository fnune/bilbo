{
  config,
  pkgs,
  ...
}: let
  hostname = "frigate.fnune.com";
  nginxPort = 8971;

  mqttBroker = builtins.head config.services.mosquitto.listeners;
  mqttPasswordVariable = "FRIGATE_MQTT_PASSWORD";

  cameraName = "indoor";
  cameraAddress = "192.168.178.109";
  cameraUser = "admin";
  cameraStream = path: "rtsp://${cameraUser}:\${CAMERA_PASSWORD}@${cameraAddress}:554/${path}#backchannel=0";

  mainStream = cameraName;
  detectStream = "${cameraName}_detect";

  restreams = {
    "${mainStream}" = cameraStream "stream0";
    "${detectStream}" = cameraStream "stream1";
  };

  restreamApi = "127.0.0.1:1984";
  restreamRtsp = "127.0.0.1:8554";
  restreamed = stream: "rtsp://${restreamRtsp}/${stream}";

  detectionResolution = 320;

  detectionWeights = pkgs.fetchurl {
    url = "https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo11n.pt";
    hash = "sha256-DrvIDUp2gNFJh6V3zSE0K2Xs/ZRjK9mo2mOuZBdkTuE=";
  };

  detectionModel =
    pkgs.runCommand "yolo11n-onnx" {
      nativeBuildInputs = [(pkgs.python3.withPackages (ps: [ps.ultralytics ps.onnx]))];
    } ''
      export HOME="$PWD" YOLO_OFFLINE=1
      cp ${detectionWeights} yolo11n.pt
      python -c "from ultralytics import YOLO; YOLO('yolo11n.pt').export(format='onnx', imgsz=${toString detectionResolution}, simplify=False)"
      install -D yolo11n.onnx $out/yolo11n.onnx
    '';

  detectionLabels = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/blakeblackshear/frigate/v${config.services.frigate.package.version}/docker/main/rootfs/labelmap/coco-80.txt";
    hash = "sha256-Srob93QvNk8vLKcApH6ukjeAc4TBo0SNj4/MSIRmc8A=";
  };

  discardStaleSharedMemory = pkgs.writeShellScript "frigate-discard-stale-shm" ''
    rm -f /dev/shm/${cameraName} /dev/shm/out-${cameraName} /dev/shm/${cameraName}_frame*
  '';

  internalApi = "http://127.0.0.1:5000/api";
  homeAssistantUser = "home_assistant";
  homeAssistantPasswordFile = "/etc/nixos/secrets/frigate-home-assistant-password";

  recordingsDirectory = "/var/lib/frigate/recordings";
  recordingsStore = "/mnt/downloads-2t/frigate/recordings";
  retainedDays = 30;
in {
  services.go2rtc = {
    enable = true;
    settings = {
      api.listen = restreamApi;
      rtsp.listen = restreamRtsp;
      streams = restreams;
    };
  };

  services.frigate = {
    enable = true;
    inherit hostname;
    vaapiDriver = "iHD";

    preCheckConfig = "export ${mqttPasswordVariable}=only-to-satisfy-the-sandbox";

    settings = {
      mqtt = {
        enabled = true;
        host = mqttBroker.address;
        port = mqttBroker.port;
        user = "frigate";
        password = "{${mqttPasswordVariable}}";
      };

      detectors.openvino = {
        type = "openvino";
        device = "GPU";
      };

      model = {
        path = "${detectionModel}/yolo11n.onnx";
        labelmap_path = detectionLabels;
        model_type = "yolo-generic";
        width = detectionResolution;
        height = detectionResolution;
        input_tensor = "nchw";
        input_dtype = "float";
      };

      ffmpeg.hwaccel_args = [];

      notifications = {
        enabled = true;
        email = "fausto.nunez@mailbox.org";
        cooldown = 60;
      };

      go2rtc.streams = restreams;

      cameras."${cameraName}" = {
        ffmpeg.inputs = [
          {
            path = restreamed detectStream;
            roles = ["detect"];
            input_args = "preset-rtsp-restream";
          }
          {
            path = restreamed mainStream;
            roles = ["record"];
            input_args = "preset-rtsp-restream";
          }
        ];

        live.streams."Main" = mainStream;

        detect = {
          enabled = true;
          width = 640;
          height = 360;
          fps = 5;
        };

        objects.track = ["person"];

        record = {
          enabled = true;
          retain.days = 0;
          alerts.retain = {
            days = retainedDays;
            mode = "motion";
          };
          detections.retain = {
            days = retainedDays;
            mode = "motion";
          };
        };

        snapshots = {
          enabled = true;
          retain.default = retainedDays;
        };
      };
    };
  };

  services.nginx.virtualHosts."${hostname}".listen = [
    {
      addr = "127.0.0.1";
      port = nginxPort;
    }
  ];

  systemd.tmpfiles.settings."10-frigate" = let
    ownedByFrigate = {
      user = "frigate";
      group = "frigate";
      mode = "0750";
    };
  in {
    "/var/lib/frigate".d = ownedByFrigate;
    "${recordingsDirectory}".L.argument = recordingsStore;
  };

  systemd.services.frigate.serviceConfig = {
    ExecStartPre = [
      "+${pkgs.coreutils}/bin/install --directory --owner frigate --group frigate --mode 0750 ${recordingsStore}"
      "+${discardStaleSharedMemory}"
    ];
    EnvironmentFile = ["/etc/nixos/secrets/frigate.env"];
  };

  systemd.services.go2rtc.serviceConfig.EnvironmentFile = ["/etc/nixos/secrets/go2rtc.env"];

  systemd.services.frigate-home-assistant-user = {
    description = "Ensure Frigate has a user for Home Assistant";
    wantedBy = ["multi-user.target"];
    after = ["frigate.service"];
    requires = ["frigate.service"];
    path = with pkgs; [curl jq];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      until curl -sf --max-time 2 ${internalApi}/version > /dev/null; do
        sleep 2
      done

      password=$(cat ${homeAssistantPasswordFile})

      exists=$(curl -sf ${internalApi}/users | jq -r --arg u ${homeAssistantUser} \
        'map(select(.username == $u)) | length')

      if [ "$exists" = "0" ]; then
        curl -sf -X POST ${internalApi}/users \
          --header 'Content-Type: application/json' \
          --data "$(jq -nc --arg u ${homeAssistantUser} --arg p "$password" \
            '{username: $u, password: $p, role: "viewer"}')" > /dev/null
      else
        curl -sf -X PUT ${internalApi}/users/${homeAssistantUser}/password \
          --header 'Content-Type: application/json' \
          --data "$(jq -nc --arg p "$password" '{password: $p}')" > /dev/null
      fi

      curl -sf ${internalApi}/users | jq -e --arg u ${homeAssistantUser} \
        'map(select(.username == $u)) | length == 1' > /dev/null
    '';
  };
}
