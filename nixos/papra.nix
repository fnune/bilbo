{...}: let
  hostname = "docs.fnune.com";
  port = 1221;

  storage = "/mnt/mirrored/papra";
  databaseDirectory = "${storage}/db";
  databaseSnapshot = "${storage}/db-snapshot";
  documentsDirectory = "${storage}/documents";
in {
  services.papra = {
    enable = true;
    environmentFile = "/etc/nixos/secrets/papra.env";
    environment = {
      APP_BASE_URL = "https://${hostname}";
      SERVER_HOSTNAME = "127.0.0.1";
      PORT = port;

      AUTH_IS_REGISTRATION_ENABLED = false;
      AUTH_IS_EMAIL_VERIFICATION_REQUIRED = true;
      AUTH_IP_ADDRESS_HEADERS = "cf-connecting-ip";

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

  systemd.services.papra.unitConfig.RequiresMountsFor = [storage];

  systemd.tmpfiles.rules = [
    "d ${storage} 0700 papra papra -"
    "d ${databaseDirectory} 0700 papra papra -"
    "d ${documentsDirectory} 0700 papra papra -"
  ];

  # Borg copies files while services run, which can catch SQLite mid-write.
  # Papra is stopped for the few seconds a copy takes, and the copy is what
  # gets restored.
  services.borgbackup.jobs.mirrored = {
    exclude = [databaseDirectory];
    preHook = ''
      (
        trap 'systemctl start papra.service' EXIT
        systemctl stop papra.service
        rm -rf ${databaseSnapshot}
        cp --archive ${databaseDirectory} ${databaseSnapshot}
      )
    '';
  };
}
