{config, ...}: let
  inherit (config.services) radarr sonarr;
  apiKey = name: {_secret = config.sops.secrets."${name}-api-key".path;};

  # A distant 1080p TV: 1080p is the target, 720p is fine, anything bigger is a last resort.
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
      # High enough to take a repack of a broken release, low enough to stop there.
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

  scoredBy = trash_ids: {
    inherit trash_ids;
    assign_scores_to = [{name = profileName;}];
  };

  # Guide scores: unwanted formats and anything without the original audio are
  # blocked; repacks of a broken release win over the original.
  # TRaSH's release-group tiers are left out on purpose: they favour the biggest encodes.
  radarrFormats = scoredBy [
    "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
    "cae4ca30163749b891686f95532519bd" # AV1
    "cc444569854e9de0b084ab2b8b1532b2" # Black and White Editions
    "ed38b889b31be83fda192888e2286d83" # BR-DISK
    "0a3f082873eb454bde444150b70253cc" # Extras
    "c465ccc73923871b3eb1802042331306" # Line/Mic Dubbed
    "90a6f9a284dff5103f6346090e6280c8" # LQ
    "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
    "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
    "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
    "dc98083864ea246d05a42df0d05f81cc" # x265 (HD)
    "923b6abef9b17f937fab56cfcf89e1f1" # DV (w/o HDR fallback)
    "d6e9318c875905d6cfb5bee961afcea9" # Language: Not Original
    "e7718d7a3ce595f289bfee26adc178f5" # Repack/Proper
    "ae43b294509409a6a13919dedd4764c4" # Repack2
    "5caaaa1c08c1742aa4342d8c4cc463f2" # Repack3
  ];
  sonarrFormats = scoredBy [
    "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
    "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
    "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
    "fbcb31d8dabd2a319072b84fc0b7249c" # Extras
    "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
    "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
    "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
    "47435ece6b99a0b477caf360e79ba0bb" # x265 (HD)
    "9b27ab6498ec0f31a3353992e19434ca" # DV (w/o HDR fallback)
    "ae575f95ab639ba5d15f663bf019e3e8" # Language: Not Original
    "ec8fa7296b64e8cd390a1600981f3923" # Repack/Proper
    "eb3d5cc0a2be0db205fb823640db6a3c" # Repack2
    "44e7c4de10ae50265753082e5dc76047" # Repack3
  ];

  # Radarr and Sonarr break ties towards the preferred size. TRaSH's ranges reach
  # 2000 MB/min, so any ratio above 0 aims at very large files; 0 aims at the minimum,
  # which still rejects microsized releases.
  smallerWithinAQuality = 0;
in {
  sops.secrets = {
    radarr-api-key = {};
    sonarr-api-key = {};
  };

  services.recyclarr = {
    enable = true;
    configuration = {
      radarr.movies = {
        base_url = "http://127.0.0.1:${toString radarr.settings.server.port}${radarr.settings.server.urlbase}";
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
        base_url = "http://127.0.0.1:${toString sonarr.settings.server.port}${sonarr.settings.server.urlbase}";
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
}
