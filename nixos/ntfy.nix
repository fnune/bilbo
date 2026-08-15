{
  config,
  lib,
  pkgs,
  ...
}: let
  hostname = "ntfy.fnune.com";
  upstream = "127.0.0.1:2586";
  stateDirectory = "/var/lib/ntfy-sh";
  authFile = "${stateDirectory}/user.db";

  account = "fausto";
  passwordFile = "/etc/nixos/secrets/ntfy-password";

  topicPrefix = "bilbo-";
  iconUrl = "https://${hostname}/icon.png";

  icon =
    pkgs.runCommand "bilbo-notification-icon" {
      nativeBuildInputs = [pkgs.librsvg];
    } ''
      install -d $out
      rsvg-convert --width 192 --height 192 ${./assets/bilbo-door.svg} --output $out/icon.png
    '';

  notify = pkgs.writeShellApplication {
    name = "bilbo-notify";
    runtimeInputs = [pkgs.curl];
    text = ''
      topic=""
      title=""
      body=""
      priority="default"

      while [ $# -gt 0 ]; do
        case "$1" in
          --topic) topic="$2"; shift 2 ;;
          --title) title="$2"; shift 2 ;;
          --body) body="$2"; shift 2 ;;
          --priority) priority="$2"; shift 2 ;;
          *) echo "bilbo-notify: unknown argument $1" >&2; exit 64 ;;
        esac
      done

      case "$topic" in
        hardware) tags="floppy_disk" ;;
        surveillance) tags="video_camera" ;;
        infra) tags="wrench" ;;
        digest) tags="newspaper" ;;
        *) echo "bilbo-notify: unknown topic $topic" >&2; exit 64 ;;
      esac

      curl --silent --show-error --fail --max-time 10 \
        --user "${account}:$(cat ${passwordFile})" \
        --header "Title: $title" \
        --header "Priority: $priority" \
        --header "Tags: $tags" \
        --header "Icon: ${iconUrl}" \
        --data-binary "$body" \
        "http://${upstream}/${topicPrefix}$topic" > /dev/null
    '';
  };

  provisionAccount = pkgs.writeShellApplication {
    name = "ntfy-provision-account";
    runtimeInputs = [config.services.ntfy-sh.package pkgs.coreutils];
    text = ''
      export NTFY_AUTH_FILE="${authFile}"
      export NTFY_AUTH_DEFAULT_ACCESS="deny-all"
      NTFY_PASSWORD="$(cat ${passwordFile})"
      export NTFY_PASSWORD

      if ! ntfy user change-pass ${account}; then
        ntfy user add ${account}
      fi

      ntfy access ${account} "${topicPrefix}*" rw

      find "${stateDirectory}/" -maxdepth 1 -name "user.db*" \
        -exec chown --reference "${stateDirectory}" {} +
    '';
  };
in {
  options.bilbo = {
    notify = lib.mkOption {
      type = lib.types.package;
      description = "Command line publisher for Bilbo's notification topics.";
    };

    notifyIcon = lib.mkOption {
      type = lib.types.package;
      description = "Directory holding the icon shown on every notification.";
    };

    notifyUpstream = lib.mkOption {
      type = lib.types.str;
      description = "Address the notification server listens on.";
    };
  };

  config = {
    bilbo = {
      inherit notify;
      notifyIcon = icon;
      notifyUpstream = upstream;
    };

    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://${hostname}";
        listen-http = upstream;
        behind-proxy = true;
        auth-file = authFile;
        auth-default-access = "deny-all";
      };
    };

    systemd.services.ntfy-provision-account = {
      description = "Give the phone an account on the notification server";
      wantedBy = ["multi-user.target"];
      after = ["ntfy-sh.service"];
      requires = ["ntfy-sh.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe provisionAccount;
      };
    };

    environment.systemPackages = [notify];
  };
}
