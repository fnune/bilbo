import json
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
import responses

from bilbo_settings import arrs

from .conftest import writes

PROFILE = "1080p, then 720p"


def config(tmp_path: Path) -> dict[str, Any]:
    (tmp_path / "settings.json").write_text(json.dumps({"main": {"apiKey": "seerr-key"}}))
    (tmp_path / "config.xml").write_text("<Config><ApiKey>prowlarr-key</ApiKey></Config>")
    arr = {"host": "127.0.0.1", "rootFolder": "/media", "categoryField": "category", "category": "Media"}
    return {
        "arrs": {
            "radarr": arr
            | {"implementation": "Radarr", "url": "http://radarr", "port": 7878, "urlBase": "/radarr"}
            | {"seerrServer": {"minimumAvailability": "released"}},
            "sonarr": arr
            | {"implementation": "Sonarr", "url": "http://sonarr", "port": 8989, "urlBase": "/sonarr"}
            | {"seerrServer": {"enableSeasonFolders": True}},
        },
        "nzbget": {"host": "127.0.0.1", "port": 6789},
        "ntfy": {"url": "http://ntfy", "topic": "bilbo"},
        "prowlarr": {
            "url": "http://prowlarr",
            "configFile": str(tmp_path / "config.xml"),
            "indexer": "NZBgeek",
        },
        "seerr": {
            "url": "http://seerr/api/v1",
            "settingsFile": str(tmp_path / "settings.json"),
            "profile": PROFILE,
            "jellyfin": {"hostname": "127.0.0.1", "port": 8096, "urlBase": "/jellyfin", "useSsl": False},
            "main": {"localLogin": False},
        },
    }


@pytest.fixture
def secrets(credentials: Callable[..., None]) -> None:
    credentials(
        radarr_username="admin",
        radarr_password="secret",
        sonarr_username="admin",
        sonarr_password="secret",
        prowlarr_username="admin",
        prowlarr_password="secret",
        radarr_api_key="radarr-key",
        sonarr_api_key="sonarr-key",
        nzbget_username="nzbget",
        nzbget_password="nzbget-secret",
        nzbgeek_api_key="nzbgeek-key",
        jellyfin_admin_username="admin",
        jellyfin_admin_password="secret",
    )


def schema(implementation: str, *fields: str) -> list[dict[str, Any]]:
    return [
        {"implementation": implementation, "fields": [{"name": field, "value": None} for field in fields]}
    ]


def serve_arr(http: responses.RequestsMock, name: str, fresh: bool) -> None:
    api = f"http://{name}/api/v3"
    http.get(f"http://{name}/ping")
    http.get(f"{api}/config/host", json={"id": 1, "username": "" if fresh else "admin"})
    http.put(f"{api}/config/host/1")
    http.get(f"{api}/rootfolder", json=[] if fresh else [{"path": "/media"}])
    http.post(f"{api}/rootfolder")
    http.get(f"{api}/downloadclient", json=[] if fresh else [{"implementation": "Nzbget"}])
    http.get(
        f"{api}/downloadclient/schema",
        json=schema("Nzbget", "host", "port", "username", "password", "category"),
    )
    http.post(f"{api}/downloadclient")
    http.get(f"{api}/notification", json=[] if fresh else [{"implementation": "Ntfy"}])
    http.get(f"{api}/notification/schema", json=schema("Ntfy", "serverUrl", "topics"))
    http.post(f"{api}/notification")
    repacks = "preferAndUpgrade" if fresh else "doNotPrefer"
    http.get(f"{api}/config/mediamanagement", json={"id": 1, "downloadPropersAndRepacks": repacks})
    http.put(f"{api}/config/mediamanagement/1")
    profiles = [{"id": 1, "name": "Any"}] + ([] if fresh else [{"id": 9, "name": PROFILE}])
    http.get(f"{api}/qualityprofile", json=profiles)
    indexers = [] if fresh else [{"id": 1, "name": "NZBgeek"}, {"id": 2, "name": "NZBgeek (Prowlarr)"}]
    http.get(f"{api}/indexer", json=indexers)
    http.delete(f"{api}/indexer/1")

    servers = (
        []
        if fresh
        else [
            {
                "id": 0,
                "isDefault": True,
                "hostname": "127.0.0.1",
                "activeProfileId": 9,
                "activeProfileName": PROFILE,
            }
        ]
    )
    http.get(f"http://seerr/api/v1/settings/{name}", json=servers)
    http.post(f"http://seerr/api/v1/settings/{name}")


def serve(http: responses.RequestsMock, fresh: bool) -> None:
    seerr = "http://seerr/api/v1"
    http.get(f"{seerr}/status")
    http.get(
        f"{seerr}/settings/public", json={"mediaServerType": 4 if fresh else 2, "initialized": not fresh}
    )
    http.post(f"{seerr}/auth/jellyfin")
    http.get(f"{seerr}/settings/jellyfin/library", json=[{"id": "movies"}, {"id": "series"}])
    http.post(f"{seerr}/settings/main")
    http.get(f"{seerr}/settings/jellyfin/users", json=[{"id": "j1"}, {"id": "j2"}])
    http.post(f"{seerr}/user/import-from-jellyfin")
    http.post(f"{seerr}/settings/initialize")
    for name in ["radarr", "sonarr"]:
        serve_arr(http, name, fresh)

    prowlarr = "http://prowlarr/api/v1"
    http.get("http://prowlarr/ping")
    http.get(f"{prowlarr}/config/host", json={"id": 1, "username": "" if fresh else "admin"})
    http.put(f"{prowlarr}/config/host/1")
    http.get(f"{prowlarr}/indexer", json=[] if fresh else [{"name": "NZBgeek"}])
    http.get(
        f"{prowlarr}/indexer/schema",
        json=[{"implementation": "Newznab", "name": "NZBgeek", "fields": [{"name": "apiKey"}]}],
    )
    http.post(f"{prowlarr}/indexer")
    applications = [] if fresh else [{"implementation": "Radarr"}, {"implementation": "Sonarr"}]
    http.get(f"{prowlarr}/applications", json=applications)
    http.get(
        f"{prowlarr}/applications/schema",
        json=schema("Radarr", "prowlarrUrl", "baseUrl", "apiKey")
        + schema("Sonarr", "prowlarrUrl", "baseUrl", "apiKey"),
    )
    http.post(f"{prowlarr}/applications")
    http.post(f"{prowlarr}/command")


def body(http: responses.RequestsMock, method: str, url: str) -> Any:
    return json.loads(
        next(
            call for call in http.calls if call.request.method == method and call.request.url == url
        ).request.body
    )


def test_configured_apps_only_get_the_settings_they_lack(
    http: responses.RequestsMock, secrets: None, tmp_path: Path
) -> None:
    serve(http, fresh=False)
    arrs.apply(config(tmp_path))

    assert writes(http) == [
        ("POST", "http://seerr/api/v1/settings/main"),
        ("POST", "http://prowlarr/api/v1/command"),
        ("DELETE", "http://radarr/api/v3/indexer/1"),
        ("DELETE", "http://sonarr/api/v3/indexer/1"),
    ]


def test_fresh_apps_get_set_up_end_to_end(
    http: responses.RequestsMock, secrets: None, tmp_path: Path
) -> None:
    serve(http, fresh=True)
    arrs.apply(config(tmp_path))

    made = writes(http)
    assert made[0] == ("POST", "http://seerr/api/v1/auth/jellyfin")
    assert made[-2:] == [
        ("POST", "http://seerr/api/v1/user/import-from-jellyfin"),
        ("POST", "http://seerr/api/v1/settings/initialize"),
    ]
    for name in ["radarr", "sonarr"]:
        api = f"http://{name}/api/v3"
        assert ("PUT", f"{api}/config/host/1") in made
        assert ("POST", f"{api}/rootfolder") in made
        assert ("PUT", f"{api}/config/mediamanagement/1") in made
        assert ("POST", f"http://seerr/api/v1/settings/{name}") in made
    assert not any(method == "DELETE" for method, _ in made)

    client = body(http, "POST", "http://radarr/api/v3/downloadclient")
    assert {field["name"]: field["value"] for field in client["fields"]} == {
        "host": "127.0.0.1",
        "port": 6789,
        "username": "nzbget",
        "password": "nzbget-secret",
        "category": "Media",
    }
    seerr_server = body(http, "POST", "http://seerr/api/v1/settings/radarr")
    assert "id" not in seerr_server
    assert seerr_server["activeProfileName"] == "Any"
    assert seerr_server["minimumAvailability"] == "released"
    assert body(http, "POST", "http://seerr/api/v1/user/import-from-jellyfin") == {
        "jellyfinUserIds": ["j1", "j2"]
    }
    indexer = body(http, "POST", "http://prowlarr/api/v1/indexer")
    assert indexer["fields"] == [{"name": "apiKey", "value": "nzbgeek-key"}]


def test_keeps_the_hand_added_indexer_until_prowlarr_has_synced(http: responses.RequestsMock) -> None:
    http.get("http://radarr/api/v3/indexer", json=[{"id": 1, "name": "NZBgeek"}])
    arrs.drop_hand_added_indexer(arrs.Api("http://radarr/api/v3"), "NZBgeek")
    assert writes(http) == []
