import json
from collections.abc import Callable

import responses

from bilbo_tools import beszel

from .conftest import writes

URL = "http://beszel"
COLLECTIONS = f"{URL}/api/collections"
CONFIG = {
    "url": URL,
    "system": "bilbo",
    "webhook": "ntfy://ntfy/bilbo",
    "alerts": [{"name": "Status", "value": 0, "min": 2}, {"name": "Disk", "value": 85, "min": 10}],
}


def test_creates_what_is_missing(http: responses.RequestsMock, credentials: Callable[..., None]) -> None:
    credentials(beszel_email="me@example.org", beszel_password="secret")
    http.get(f"{URL}/api/health")
    http.post(f"{COLLECTIONS}/_superusers/auth-with-password", json={"token": "token"})
    http.get(f"{COLLECTIONS}/users/records", json={"items": []})
    http.post(f"{COLLECTIONS}/users/records", json={"id": "user"})
    http.get(f"{COLLECTIONS}/user_settings/records", json={"items": []})
    http.post(f"{COLLECTIONS}/user_settings/records", json={"id": "settings"})
    http.get(f"{COLLECTIONS}/user_settings/records/settings", json={"settings": {"chartTime": "1h"}})
    http.patch(f"{COLLECTIONS}/user_settings/records/settings")
    http.get(f"{COLLECTIONS}/systems/records", json={"items": [{"id": "system"}]})
    http.get(f"{COLLECTIONS}/alerts/records", json={"items": [{"name": "Status"}]})
    http.post(f"{COLLECTIONS}/alerts/records")

    beszel.apply(CONFIG)

    assert writes(http) == [
        ("POST", f"{COLLECTIONS}/_superusers/auth-with-password"),
        ("POST", f"{COLLECTIONS}/users/records"),
        ("POST", f"{COLLECTIONS}/user_settings/records"),
        ("PATCH", f"{COLLECTIONS}/user_settings/records/settings"),
        ("POST", f"{COLLECTIONS}/alerts/records"),
    ]
    webhook = next(call for call in http.calls if call.request.method == "PATCH")
    assert json.loads(webhook.request.body) == {
        "settings": {"chartTime": "1h", "webhooks": ["ntfy://ntfy/bilbo"]}
    }
    alert = next(
        call for call in http.calls if call.request.method == "POST" and "alerts" in call.request.url
    )
    assert json.loads(alert.request.body) == {
        "name": "Disk",
        "value": 85,
        "min": 10,
        "user": "user",
        "system": "system",
    }


def test_leaves_a_configured_hub_alone(
    http: responses.RequestsMock, credentials: Callable[..., None]
) -> None:
    credentials(beszel_email="me@example.org", beszel_password="secret")
    http.get(f"{URL}/api/health")
    http.post(f"{COLLECTIONS}/_superusers/auth-with-password", json={"token": "token"})
    http.get(f"{COLLECTIONS}/users/records", json={"items": [{"id": "user"}]})
    http.patch(f"{COLLECTIONS}/users/records/user")
    http.get(f"{COLLECTIONS}/user_settings/records", json={"items": [{"id": "settings"}]})
    http.get(
        f"{COLLECTIONS}/user_settings/records/settings",
        json={"settings": {"webhooks": ["ntfy://ntfy/bilbo"]}},
    )
    http.get(f"{COLLECTIONS}/systems/records", json={"items": [{"id": "system"}]})
    http.get(f"{COLLECTIONS}/alerts/records", json={"items": [{"name": "Status"}, {"name": "Disk"}]})

    beszel.apply(CONFIG)

    assert writes(http) == [
        ("POST", f"{COLLECTIONS}/_superusers/auth-with-password"),
        ("PATCH", f"{COLLECTIONS}/users/records/user"),
    ]
