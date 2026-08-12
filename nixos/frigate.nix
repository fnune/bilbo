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

  frigatePackage = config.services.frigate.package;
  frigateImage = "docker://ghcr.io/blakeblackshear/frigate:${frigatePackage.version}";
  openvinoModelDirectory = "/var/lib/frigate/openvino-model";
  openvinoModel = "${openvinoModelDirectory}/ssdlite_mobilenet_v2.xml";

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
        path = openvinoModel;
        labelmap_path = "${frigatePackage}/share/frigate/coco_91cl_bkgr.txt";
        width = 300;
        height = 300;
        input_tensor = "nhwc";
        input_pixel_format = "bgr";
      };

      ffmpeg.hwaccel_args = [];

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
    "${recordingsStore}".d = ownedByFrigate;
    "${recordingsDirectory}".L.argument = recordingsStore;
  };

  systemd.services.go2rtc.serviceConfig.EnvironmentFile = ["/etc/nixos/secrets/go2rtc.env"];

  systemd.services.frigate-openvino-model = {
    description = "Extract the OpenVINO detection model from the Frigate container image";
    requiredBy = ["frigate.service"];
    before = ["frigate.service"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    path = with pkgs; [gnutar gzip skopeo];
    environment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      CacheDirectory = "frigate-openvino-model";
    };

    script = ''
      if [ -e ${openvinoModel} ]; then
        exit 0
      fi

      unpacked="$CACHE_DIRECTORY/image"
      rm -rf "$unpacked"
      skopeo --insecure-policy copy --quiet ${frigateImage} dir:"$unpacked"

      install --directory --owner frigate --group frigate --mode 0750 ${openvinoModelDirectory}
      for layer in "$unpacked"/*; do
        if tar --extract --file "$layer" --directory ${openvinoModelDirectory} \
             --strip-components 1 openvino-model 2> "$CACHE_DIRECTORY/tar-error"; then
          break
        fi
      done
      rm -rf "$unpacked"

      chown --recursive frigate:frigate ${openvinoModelDirectory}

      if [ ! -e ${openvinoModel} ]; then
        echo "no layer of ${frigateImage} yielded openvino-model; last tar error:" >&2
        cat "$CACHE_DIRECTORY/tar-error" >&2
        exit 1
      fi
    '';
  };
}
