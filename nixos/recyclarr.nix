{
  config,
  mkSettingsService,
  pkgs,
  servarrUrl,
  ...
}: let
  apiKey = name: {_secret = config.sops.secrets."${name}-api-key".path;};

  profileName = "1080p, then 720p";
  hd1080p = "1080p";

  profile = {
    remux1080p,
    uhd,
  }: {
    name = profileName;
    reset_unmatched_scores.enabled = true;
    upgrade = {
      allowed = true;
      until_quality = hd1080p;
      until_score = 10;
    };
    min_format_score = 0;
    qualities = [
      {
        name = hd1080p;
        qualities = ["Bluray-1080p" "WEBDL-1080p" "WEBRip-1080p"];
      }
      {
        name = "720p";
        qualities = ["Bluray-720p" "WEBDL-720p" "WEBRip-720p"];
      }
      {name = remux1080p;}
      {
        name = "2160p";
        qualities = uhd;
      }
    ];
  };

  scoredBy = formats: {
    trash_ids = builtins.attrValues formats;
    assign_scores_to = [{name = profileName;}];
  };

  radarrFormats = scoredBy {
    "3D" = "b8cd450cbfa689c0259a01d9e29ba3d6";
    "AV1" = "cae4ca30163749b891686f95532519bd";
    "Black and White Editions" = "cc444569854e9de0b084ab2b8b1532b2";
    "BR-DISK" = "ed38b889b31be83fda192888e2286d83";
    "Extras" = "0a3f082873eb454bde444150b70253cc";
    "Line/Mic Dubbed" = "c465ccc73923871b3eb1802042331306";
    "LQ" = "90a6f9a284dff5103f6346090e6280c8";
    "LQ (Release Title)" = "e204b80c87be9497a8a6eaff48f72905";
    "Sing-Along Versions" = "712d74cd88bceb883ee32f773656b1f5";
    "Upscaled" = "bfd8eb01832d646a0a89c4deb46f8564";
    "x265 (HD)" = "dc98083864ea246d05a42df0d05f81cc";
    "DV (w/o HDR fallback)" = "923b6abef9b17f937fab56cfcf89e1f1";
    "Language: Not Original" = "d6e9318c875905d6cfb5bee961afcea9";
    "Repack/Proper" = "e7718d7a3ce595f289bfee26adc178f5";
    "Repack2" = "ae43b294509409a6a13919dedd4764c4";
    "Repack3" = "5caaaa1c08c1742aa4342d8c4cc463f2";
  };
  sonarrFormats = scoredBy {
    "AV1" = "15a05bc7c1a36e2b57fd628f8977e2fc";
    "Bad Dual Groups" = "32b367365729d530ca1c124a0b180c64";
    "BR-DISK" = "85c61753df5da1fb2aab6f2a47426b09";
    "Extras" = "fbcb31d8dabd2a319072b84fc0b7249c";
    "LQ" = "9c11cd3f07101cdba90a2d81cf0e56b4";
    "LQ (Release Title)" = "e2315f990da2e2cbfc9fa5b7a6fcfe48";
    "Upscaled" = "23297a736ca77c0fc8e70f8edd7ee56c";
    "x265 (HD)" = "47435ece6b99a0b477caf360e79ba0bb";
    "DV (w/o HDR fallback)" = "9b27ab6498ec0f31a3353992e19434ca";
    "Language: Not Original" = "ae575f95ab639ba5d15f663bf019e3e8";
    "Repack/Proper" = "ec8fa7296b64e8cd390a1600981f3923";
    "Repack2" = "eb3d5cc0a2be0db205fb823640db6a3c";
    "Repack3" = "44e7c4de10ae50265753082e5dc76047";
  };

  # Ties go to the size closest to "preferred". TRaSH's ranges reach 2000 MB/min, so any ratio
  # above 0 favours huge files; 0 favours the smallest file that passes the minimum.
  smallerWithinAQuality = 0;
in {
  services.recyclarr = {
    enable = true;
    configuration = {
      radarr.movies = {
        base_url = servarrUrl "radarr";
        api_key = apiKey "radarr";
        quality_definition = {
          type = "movie";
          preferred_ratio = smallerWithinAQuality;
        };
        quality_profiles = [
          (profile {
            remux1080p = "Remux-1080p";
            uhd = ["WEBDL-2160p" "WEBRip-2160p" "Bluray-2160p" "Remux-2160p"];
          })
        ];
        custom_formats = [radarrFormats];
      };
      sonarr.series = {
        base_url = servarrUrl "sonarr";
        api_key = apiKey "sonarr";
        quality_definition = {
          type = "series";
          preferred_ratio = smallerWithinAQuality;
        };
        quality_profiles = [
          (profile {
            remux1080p = "Bluray-1080p Remux";
            uhd = ["WEBDL-2160p" "WEBRip-2160p" "Bluray-2160p" "Bluray-2160p Remux"];
          })
        ];
        custom_formats = [sonarrFormats];
      };
    };
  };

  # The timer alone would leave a changed profile unsynced until the next night.
  systemd.services.recyclarr-on-change = mkSettingsService {
    name = "recyclarr-on-change";
    description = "Sync Recyclarr right after its configuration changes";
    after = ["radarr" "sonarr"];
    restartTriggers = [config.systemd.services.recyclarr.preStart];
    runtimeInputs = [pkgs.systemd];
    text = ''
      wait_until_up ${servarrUrl "radarr"}/ping
      wait_until_up ${servarrUrl "sonarr"}/ping
      systemctl start recyclarr.service
    '';
  };
}
