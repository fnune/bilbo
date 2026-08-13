{
  config,
  pkgs,
  ...
}: let
  hostname = "frigate.fnune.com";
  nginxPort = 8971;

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

    settings = {
      mqtt.enabled = false;

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

  systemd.services.frigate.serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/install --directory --owner frigate --group frigate --mode 0750 ${recordingsStore}"
  ];

  systemd.services.go2rtc.serviceConfig.EnvironmentFile = ["/etc/nixos/secrets/go2rtc.env"];
}
