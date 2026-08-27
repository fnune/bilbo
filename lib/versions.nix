system: let
  inherit (system) config pkgs;
  inherit (system.pkgs) lib;
  inherit (builtins) attrNames concatMap elem filter isAttrs isString listToAttrs;

  orElse = fallback: expr: let
    attempt = builtins.tryEval expr;
  in
    if attempt.success && attempt.value != null
    then attempt.value
    else fallback;

  entry = label: package: let
    name = orElse null (
      if isAttrs package && isString (package.name or null)
      then package.name
      else null
    );
  in
    lib.optional (name != null) {
      name = label;
      value = {
        inherit name;
        version = orElse "" (package.version or "");
      };
    };

  entriesAt = paths:
    concatMap (
      path: entry (lib.concatStringsSep "." path) (orElse null (lib.attrByPath path null pkgs))
    )
    paths;

  optionsSafeToRead = let
    unitNames = attrNames config.systemd.services;
  in
    filter (name: elem name unitNames) (attrNames config.services);

  enabledServices =
    concatMap (
      name: let
        service = orElse null config.services.${name};
        enabled = orElse false ((service.enable or false) == true);
      in
        lib.optionals enabled (entry name (service.package or null))
    )
    optionsSafeToRead;

  unmatchedServices = entriesAt [
    ["immich"]
    ["filebrowser"]
    ["home-assistant-custom-components" "frigate"]
    ["home-assistant-custom-lovelace-modules" "advanced-camera-card"]
  ];

  unmatchedPlatform = entriesAt [
    ["jellyfin-ffmpeg"]
    ["intel-media-driver"]
    ["intel-vaapi-driver"]
    ["nodejs_22"]
    ["rclone"]
  ];
in {
  services = listToAttrs (enabledServices ++ unmatchedServices);
  platform = listToAttrs (entry "kernel" config.boot.kernelPackages.kernel ++ unmatchedPlatform);
  system =
    listToAttrs
    (concatMap (package: entry (orElse "?" (package.pname or package.name)) package)
      (orElse [] config.environment.systemPackages));
}
