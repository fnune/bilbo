from typing import Any

from .api import Api, credential, has, wait_until_up


def apply(config: dict[str, Any]) -> None:
    url = config["url"]
    email = credential("beszel-email")
    password = credential("beszel-password")
    wait_until_up(f"{url}/api/health")

    token = Api(url).post(
        "/api/collections/_superusers/auth-with-password",
        json={"identity": email, "password": password},
    )["token"]
    beszel = Api(f"{url}/api/collections", {"Authorization": token})

    user = ensure_admin_user(beszel, email, password)
    add_webhook(beszel, user, config["webhook"])

    system = first(beszel, "systems", f"name='{config['system']}'")
    if system is None:
        raise LookupError(f"Beszel has no system named {config['system']}")
    existing = beszel.get("/alerts/records", params={"filter": f"user='{user}' && system='{system}'"})[
        "items"
    ]
    for alert in config["alerts"]:
        if not has(existing, name=alert["name"]):
            beszel.post("/alerts/records", json=alert | {"user": user, "system": system})


def first(beszel: Api, collection: str, filter_expression: str) -> str | None:
    items = beszel.get(f"/{collection}/records", params={"filter": filter_expression, "perPage": 1})["items"]
    return items[0]["id"] if items else None


def ensure_admin_user(beszel: Api, email: str, password: str) -> str:
    user = first(beszel, "users", f"email='{email}'")
    if user is None:
        return beszel.post(
            "/users/records",
            json={
                "email": email,
                "password": password,
                "passwordConfirm": password,
                "verified": True,
                "role": "admin",
            },
        )["id"]
    beszel.patch(f"/users/records/{user}", json={"role": "admin", "verified": True})
    return user


def add_webhook(beszel: Api, user: str, webhook: str) -> None:
    record = first(beszel, "user_settings", f"user='{user}'")
    if record is None:
        record = beszel.post("/user_settings/records", json={"user": user})["id"]
    settings = beszel.get(f"/user_settings/records/{record}")["settings"]
    webhooks = settings.get("webhooks", [])
    if webhook in webhooks:
        return
    beszel.patch(
        f"/user_settings/records/{record}",
        json={"settings": settings | {"webhooks": [*webhooks, webhook]}},
    )
