import json
from collections.abc import Callable

import responses

from bilbo_settings import jellyfin

from .conftest import writes

URL = "http://jellyfin"
CONFIG = {
    "url": URL,
    "client": 'MediaBrowser Client="test"',
    "libraries": {"Movies": {"collectionType": "movies", "path": "/media/Movies"}},
    "userPlayback": {"SubtitleMode": "Smart"},
    "libraryOptions": {"SubtitleDownloadLanguages": []},
    "network": {"KnownProxies": ["127.0.0.1"]},
    "startup": {"UICulture": "en-US"},
}


def serve(http: responses.RequestsMock, wizard_done: bool, libraries: list[str]) -> None:
    http.get(f"{URL}/System/Info/Public", json={"StartupWizardCompleted": wizard_done})
    http.get(f"{URL}/Startup/User", json={})
    for path in ["/Startup/Configuration", "/Startup/User", "/Startup/Complete"]:
        http.post(f"{URL}{path}")
    http.post(f"{URL}/Users/AuthenticateByName", json={"AccessToken": "token"})
    http.get(
        f"{URL}/Library/VirtualFolders",
        json=[
            {"ItemId": "1", "Locations": libraries, "LibraryOptions": {"SubtitleDownloadLanguages": ["eng"]}}
        ],
    )
    http.post(f"{URL}/Library/VirtualFolders")
    http.get(f"{URL}/Users", json=[{"Id": "u1", "Configuration": {"SubtitleMode": "Always", "Other": 1}}])
    http.post(f"{URL}/Users/Configuration")
    http.get(f"{URL}/System/Configuration/network", json={"KnownProxies": [], "BaseUrl": "/jellyfin"})
    http.post(f"{URL}/System/Configuration/network")
    http.post(f"{URL}/Library/VirtualFolders/LibraryOptions")


def test_configured_server_only_gets_settings(
    http: responses.RequestsMock, credentials: Callable[..., None]
) -> None:
    credentials(jellyfin_admin_username="admin", jellyfin_admin_password="secret")
    serve(http, wizard_done=True, libraries=["/media/Movies"])
    jellyfin.apply(CONFIG)

    assert writes(http) == [
        ("POST", f"{URL}/Users/AuthenticateByName"),
        ("POST", f"{URL}/Users/Configuration"),
        ("POST", f"{URL}/System/Configuration/network"),
        ("POST", f"{URL}/Library/VirtualFolders/LibraryOptions"),
    ]
    user_update = next(
        call for call in http.calls if call.request.url.startswith(f"{URL}/Users/Configuration")
    )
    assert json.loads(user_update.request.body) == {"SubtitleMode": "Smart", "Other": 1}
    network_update = next(
        call
        for call in http.calls
        if call.request.url == f"{URL}/System/Configuration/network" and call.request.method == "POST"
    )
    assert json.loads(network_update.request.body) == {"KnownProxies": ["127.0.0.1"], "BaseUrl": "/jellyfin"}


def test_fresh_server_runs_the_wizard_and_adds_libraries(
    http: responses.RequestsMock, credentials: Callable[..., None]
) -> None:
    credentials(jellyfin_admin_username="admin", jellyfin_admin_password="secret")
    serve(http, wizard_done=False, libraries=[])
    jellyfin.apply(CONFIG)

    made = writes(http)
    assert made[:3] == [
        ("POST", f"{URL}/Startup/Configuration"),
        ("POST", f"{URL}/Startup/User"),
        ("POST", f"{URL}/Startup/Complete"),
    ]
    assert ("POST", f"{URL}/Library/VirtualFolders") in made
    startup_user = next(
        call
        for call in http.calls
        if call.request.url == f"{URL}/Startup/User" and call.request.method == "POST"
    )
    assert json.loads(startup_user.request.body) == {"Name": "admin", "Password": "secret"}
