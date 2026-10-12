from typing import Any

from .api import Api, credential, wait_until_up


def apply(config: dict[str, Any]) -> None:
    url = config["url"]
    username = credential("jellyfin-admin-username")
    password = credential("jellyfin-admin-password")
    anonymous = Api(url, {"Authorization": config["client"]})

    wait_until_up(f"{url}/System/Info/Public")
    if not anonymous.get("/System/Info/Public")["StartupWizardCompleted"]:
        run_startup_wizard(anonymous, config["startup"], username, password)

    token = anonymous.post("/Users/AuthenticateByName", json={"Username": username, "Pw": password})[
        "AccessToken"
    ]
    jellyfin = Api(url, {"Authorization": f'{config["client"]}, Token="{token}"'})

    add_missing_libraries(jellyfin, config["libraries"])
    for user in jellyfin.get("/Users"):
        jellyfin.post(
            "/Users/Configuration",
            params={"userId": user["Id"]},
            json=user["Configuration"] | config["userPlayback"],
        )
    jellyfin.post(
        "/System/Configuration/network",
        json=jellyfin.get("/System/Configuration/network") | config["network"],
    )
    for library in jellyfin.get("/Library/VirtualFolders"):
        jellyfin.post(
            "/Library/VirtualFolders/LibraryOptions",
            json={
                "Id": library["ItemId"],
                "LibraryOptions": library["LibraryOptions"] | config["libraryOptions"],
            },
        )


def run_startup_wizard(anonymous: Api, startup: dict[str, Any], username: str, password: str) -> None:
    anonymous.post("/Startup/Configuration", json=startup)
    anonymous.get("/Startup/User")
    anonymous.post("/Startup/User", json={"Name": username, "Password": password})
    anonymous.post("/Startup/Complete")


def add_missing_libraries(jellyfin: Api, libraries: dict[str, dict[str, str]]) -> None:
    existing_paths = {
        path for library in jellyfin.get("/Library/VirtualFolders") for path in library["Locations"]
    }
    for name, library in libraries.items():
        if library["path"] in existing_paths:
            continue
        jellyfin.post(
            "/Library/VirtualFolders",
            params={
                "name": name,
                "collectionType": library["collectionType"],
                "paths": library["path"],
                "refreshLibrary": "true",
            },
            json={"LibraryOptions": {}},
        )
