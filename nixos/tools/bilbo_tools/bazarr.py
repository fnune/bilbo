from pathlib import Path
from typing import Any

import yaml

from .api import Api, credential, wait_until_up


def apply(config: dict[str, Any]) -> None:
    url = config["url"]
    api_key = yaml.safe_load(Path(config["configFile"]).read_text())["auth"]["apikey"]
    bazarr = Api(url, {"X-API-KEY": api_key})
    wait_until_up(url)

    secret_fields = [(field, credential(name)) for field, name in config["secretFields"].items()]
    bazarr.post("/system/settings", data=config["fields"] + secret_fields)

    assign_profile(bazarr, "series", "seriesid", "sonarrSeriesId", config["profileId"])
    assign_profile(bazarr, "movies", "radarrid", "radarrId", config["profileId"])


def assign_profile(bazarr: Api, endpoint: str, id_parameter: str, id_field: str, profile_id: int) -> None:
    items = [item[id_field] for item in bazarr.get(f"/{endpoint}")["data"] if item["profileId"] != profile_id]
    if not items:
        return
    bazarr.post(
        f"/{endpoint}",
        data=[(id_parameter, item) for item in items] + [("profileid", profile_id) for _ in items],
    )
