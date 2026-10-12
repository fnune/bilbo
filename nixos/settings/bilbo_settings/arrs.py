import json
from pathlib import Path
from typing import Any

from .api import Api, credential, has, wait_until_up

SEERR_NOT_CONFIGURED = 4
SEERR_JELLYFIN = 2


def apply(config: dict[str, Any]) -> None:
    arrs = {
        name: Api(f"{arr['url']}/api/v3", {"X-Api-Key": credential(f"{name}-api-key")})
        for name, arr in config["arrs"].items()
    }

    seerr = set_up_seerr(config["seerr"])

    for name, arr in config["arrs"].items():
        wait_until_up(f"{arr['url']}/ping")
        apply_arr(arrs[name], name, arr, config)
        connect_seerr(seerr, arrs[name], name, arr, config["seerr"]["profile"])

    prowlarr_config = config["prowlarr"]
    prowlarr = Api(
        f"{prowlarr_config['url']}/api/v1", {"X-Api-Key": prowlarr_api_key(prowlarr_config["configFile"])}
    )
    wait_until_up(f"{prowlarr_config['url']}/ping")
    apply_prowlarr(prowlarr, prowlarr_config, config["arrs"])
    for name in config["arrs"]:
        drop_hand_added_indexer(arrs[name], prowlarr_config["indexer"])

    finish_seerr_setup(seerr, config["seerr"])


def ensure_login(api: Api, app: str) -> None:
    username = credential(f"{app}-username")
    password = credential(f"{app}-password")
    host = api.get("/config/host")
    if host["username"] == username:
        return
    api.put(
        f"/config/host/{host['id']}",
        json=host
        | {
            "username": username,
            "password": password,
            "passwordConfirmation": password,
            "authenticationMethod": "forms",
            "authenticationRequired": "enabled",
        },
    )


def from_schema(
    api: Api, path: str, implementation: str, fields: dict[str, Any], **properties: Any
) -> dict[str, Any]:
    schema = next(item for item in api.get(f"{path}/schema") if item["implementation"] == implementation)
    schema["fields"] = [
        field | {"value": fields[field["name"]]} if field["name"] in fields else field
        for field in schema["fields"]
    ]
    return schema | properties


def apply_arr(api: Api, name: str, arr: dict[str, Any], config: dict[str, Any]) -> None:
    ensure_login(api, name)

    if not has(api.get("/rootfolder"), path=arr["rootFolder"]):
        api.post("/rootfolder", json={"path": arr["rootFolder"]})

    if not has(api.get("/downloadclient"), implementation="Nzbget"):
        nzbget = config["nzbget"]
        api.post(
            "/downloadclient",
            json=from_schema(
                api,
                "/downloadclient",
                "Nzbget",
                {
                    "host": nzbget["host"],
                    "port": nzbget["port"],
                    "username": credential("nzbget-username"),
                    "password": credential("nzbget-password"),
                    arr["categoryField"]: arr["category"],
                },
                name="NZBGet",
                enable=True,
                removeCompletedDownloads=True,
                removeFailedDownloads=True,
            ),
        )

    if not has(api.get("/notification"), implementation="Ntfy"):
        ntfy = config["ntfy"]
        api.post(
            "/notification",
            json=from_schema(
                api,
                "/notification",
                "Ntfy",
                {"serverUrl": ntfy["url"], "topics": [ntfy["topic"]]},
                name="ntfy",
                onGrab=True,
                onDownload=True,
                onUpgrade=True,
                onHealthIssue=True,
            ),
        )

    media_management = api.get("/config/mediamanagement")
    if media_management["downloadPropersAndRepacks"] != "doNotPrefer":
        api.put(
            f"/config/mediamanagement/{media_management['id']}",
            json=media_management | {"downloadPropersAndRepacks": "doNotPrefer"},
        )


def prowlarr_api_key(config_file: str) -> str:
    config = Path(config_file).read_text()
    return config.split("<ApiKey>", 1)[1].split("</ApiKey>", 1)[0]


def apply_prowlarr(prowlarr: Api, config: dict[str, Any], arrs: dict[str, Any]) -> None:
    ensure_login(prowlarr, "prowlarr")

    indexer = config["indexer"]
    if not has(prowlarr.get("/indexer"), name=indexer):
        definition = next(
            (
                item
                for item in prowlarr.get("/indexer/schema")
                if item["implementation"] == "Newznab" and item["name"].lower() == indexer.lower()
            ),
            None,
        )
        if definition is None:
            raise LookupError(f"Prowlarr has no {indexer} indexer definition")
        definition["fields"] = [
            field | {"value": credential("nzbgeek-api-key")} if field["name"] == "apiKey" else field
            for field in definition["fields"]
        ]
        prowlarr.post("/indexer", json=definition | {"name": indexer, "enable": True, "appProfileId": 1})

    applications = prowlarr.get("/applications")
    for name, arr in arrs.items():
        if has(applications, implementation=arr["implementation"]):
            continue
        prowlarr.post(
            "/applications",
            json=from_schema(
                prowlarr,
                "/applications",
                arr["implementation"],
                {
                    "prowlarrUrl": config["url"],
                    "baseUrl": arr["url"],
                    "apiKey": credential(f"{name}-api-key"),
                },
                name=arr["implementation"],
                syncLevel="fullSync",
            ),
        )
    prowlarr.post("/command", json={"name": "ApplicationIndexerSync"})


def drop_hand_added_indexer(arr: Api, name: str) -> None:
    indexers = arr.get("/indexer")
    if not any(indexer["name"].endswith("(Prowlarr)") for indexer in indexers):
        return
    for indexer in indexers:
        if indexer["name"] == name:
            arr.delete(f"/indexer/{indexer['id']}")


def set_up_seerr(config: dict[str, Any]) -> Api:
    url = config["url"]
    wait_until_up(f"{url}/status")

    if Api(url).get("/settings/public")["mediaServerType"] == SEERR_NOT_CONFIGURED:
        Api(url).post(
            "/auth/jellyfin",
            json={
                "username": credential("jellyfin-admin-username"),
                "password": credential("jellyfin-admin-password"),
                "serverType": SEERR_JELLYFIN,
            }
            | config["jellyfin"],
        )
        seerr = seerr_api(config)
        library_ids = [
            library["id"] for library in seerr.get("/settings/jellyfin/library", params={"sync": "true"})
        ]
        seerr.get("/settings/jellyfin/library", params={"enable": ",".join(library_ids)})

    seerr = seerr_api(config)
    seerr.post("/settings/main", json=config["main"])
    return seerr


def seerr_api(config: dict[str, Any]) -> Api:
    api_key = json.loads(Path(config["settingsFile"]).read_text())["main"]["apiKey"]
    return Api(config["url"], {"X-Api-Key": api_key})


def connect_seerr(seerr: Api, arr: Api, name: str, config: dict[str, Any], profile_name: str) -> None:
    profiles = arr.get("/qualityprofile")
    preferred = next((profile for profile in profiles if profile["name"] == profile_name), None)
    servers = seerr.get(f"/settings/{name}")

    if not servers:
        profile = preferred or profiles[0]
        seerr.post(
            f"/settings/{name}",
            json={
                "name": config["implementation"],
                "hostname": config["host"],
                "port": config["port"],
                "baseUrl": config["urlBase"],
                "useSsl": False,
                "apiKey": credential(f"{name}-api-key"),
                "activeProfileId": profile["id"],
                "activeProfileName": profile["name"],
                "activeDirectory": config["rootFolder"],
                "is4k": False,
                "isDefault": True,
                "syncEnabled": True,
                "preventSearch": False,
                "tags": [],
            }
            | config["seerrServer"],
        )
        return

    for server in servers:
        if not server["isDefault"]:
            continue
        wanted = server | {"hostname": config["host"]}
        if preferred:
            wanted |= {"activeProfileId": preferred["id"], "activeProfileName": preferred["name"]}
        if wanted != server:
            seerr.put(
                f"/settings/{name}/{server['id']}",
                json={key: value for key, value in wanted.items() if key != "id"},
            )


def finish_seerr_setup(seerr: Api, config: dict[str, Any]) -> None:
    if Api(config["url"]).get("/settings/public")["initialized"]:
        return
    user_ids = [user["id"] for user in seerr.get("/settings/jellyfin/users")]
    seerr.post("/user/import-from-jellyfin", json={"jellyfinUserIds": user_ids})
    seerr.post("/settings/initialize")
