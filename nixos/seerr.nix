{config, ...}: {
  services.seerr.enable = true;

  bilbo.backups.seerr.paths = [config.services.seerr.configDir];
}
