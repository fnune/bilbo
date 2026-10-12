{
  config,
  pkgs,
  ...
}: let
  port = 3000;
  immich = config.services.immich;
in {
  services.immich.host = "127.0.0.1"; # the proxy resolves localhost to IPv4 only

  services.immich-public-proxy = {
    enable = true;
    package = pkgs.unstable.immich-public-proxy; # 1.15.6 crashes on Immich 3 share links
    immichUrl = "http://${immich.host}:${toString immich.port}";
    inherit port;
  };

  # MemoryDenyWriteExecute stays off for the V8 JIT.
  systemd.services.immich-public-proxy.serviceConfig = {
    LockPersonality = true;
    ProcSubset = "pid";
    ProtectProc = "invisible";
    SystemCallArchitectures = "native";
    SystemCallFilter = ["@system-service" "~@privileged"];
    SystemCallErrorNumber = "EPERM";
    UMask = "0077";
  };
}
