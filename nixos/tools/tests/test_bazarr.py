from collections.abc import Callable
from pathlib import Path
from urllib.parse import parse_qs

import responses

from bilbo_tools import bazarr

URL = "http://bazarr/api"


def test_posts_settings_with_secrets_and_assigns_the_profile(
    http: responses.RequestsMock, credentials: Callable[..., None], tmp_path: Path
) -> None:
    credentials(bazarr_password="hunter2")
    config_file = tmp_path / "config.yaml"
    config_file.write_text("auth:\n  apikey: key\n")
    http.get(URL)
    http.post(f"{URL}/system/settings")
    http.get(
        f"{URL}/series",
        json={"data": [{"sonarrSeriesId": 1, "profileId": 1}, {"sonarrSeriesId": 2, "profileId": None}]},
    )
    http.post(f"{URL}/series")
    http.get(f"{URL}/movies", json={"data": [{"radarrId": 7, "profileId": 1}]})

    bazarr.apply(
        {
            "url": URL,
            "configFile": str(config_file),
            "profileId": 1,
            "fields": [["languages-enabled", "en"], ["languages-enabled", "es"]],
            "secretFields": {"settings-auth-password": "bazarr-password"},
        }
    )

    settings = next(call for call in http.calls if call.request.url == f"{URL}/system/settings")
    assert settings.request.headers["X-API-KEY"] == "key"
    assert parse_qs(settings.request.body) == {
        "languages-enabled": ["en", "es"],
        "settings-auth-password": ["hunter2"],
    }
    series_update = [
        call for call in http.calls if call.request.url == f"{URL}/series" and call.request.method == "POST"
    ]
    assert [parse_qs(call.request.body) for call in series_update] == [
        {"seriesid": ["2"], "profileid": ["1"]}
    ]
    assert not any(
        call.request.url == f"{URL}/movies" and call.request.method == "POST" for call in http.calls
    )
