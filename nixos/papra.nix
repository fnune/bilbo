{
  bilboToolsCommand,
  config,
  ...
}: let
  hostname = "docs.fnune.com";
  port = 1221;

  storage = "/mnt/mirrored/papra";
  databaseDirectory = "${storage}/db";
  documentsDirectory = "${storage}/documents";
in {
  sops.secrets = {
    papra-env = {};
    papra-api-key.owner = "fausto";
    papra-anthropic-api-key = {};
  };

  services.papra = {
    enable = true;
    environmentFile = config.sops.secrets.papra-env.path;
    environment = {
      APP_BASE_URL = "https://${hostname}";
      SERVER_HOSTNAME = "127.0.0.1";
      PORT = port;

      AUTH_IS_REGISTRATION_ENABLED = false;
      AUTH_IS_EMAIL_VERIFICATION_REQUIRED = true;
      AUTH_IP_ADDRESS_HEADERS = "x-forwarded-for";

      DATABASE_URL = "file:${databaseDirectory}/db.sqlite";

      DOCUMENT_STORAGE_FILESYSTEM_ROOT = documentsDirectory;
      DOCUMENT_STORAGE_ENCRYPTION_IS_ENABLED = true;
      DOCUMENT_STORAGE_USE_LEGACY_STORAGE_KEY_DEFINITION_SYSTEM = false;
      DOCUMENT_STORAGE_KEY_PATTERN = "{{organization.id}}/{{currentDate.yyyy}}/{{currentDate.MM}}/{{document.name}}";

      DOCUMENTS_OCR_LANGUAGES = "deu,eng,spa";

      AI_IS_ENABLED = true;
      AI_DEFAULT_MODEL = "anthropic://claude-haiku-4-5";

      INGESTION_FOLDER_IS_ENABLED = false;
      INTAKE_EMAILS_IS_ENABLED = false;
    };
  };

  systemd.services = {
    papra.unitConfig.RequiresMountsFor = [storage];
    papra-dates = {
      description = "Date undated Papra documents from their names or text";
      after = ["papra.service" "borgbackup-job-mirrored.service"];
      wants = ["papra.service"];
      startAt = "0/4:00";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "papra-dates";
        ExecStart = bilboToolsCommand "papra-dates" {
          url = "http://127.0.0.1:${toString port}";
          model = "claude-haiku-5-5";
          askedFile = "/var/lib/papra-dates/asked";
        };
        LoadCredential = [
          "papra-api-key:${config.sops.secrets.papra-api-key.path}"
          "anthropic-api-key:${config.sops.secrets.papra-anthropic-api-key.path}"
        ];
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${storage} 0700 papra papra -"
    "d ${databaseDirectory} 0700 papra papra -"
    "d ${documentsDirectory} 0700 papra papra -"
  ];

  bilbo.backups.papra.stopToCopy = {
    service = "papra";
    directory = databaseDirectory;
  };
}
