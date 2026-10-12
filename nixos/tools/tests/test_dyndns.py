import json
from collections.abc import Callable

import responses

from bilbo_tools import dyndns

from .conftest import writes

CLOUDFLARE = "https://api.cloudflare.com/client/v4"
CONFIG = {
    "addressUrl": "https://ip.example",
    "zone": "example.org",
    "hostnames": ["new.example.org", "old.example.org", "same.example.org"],
}


def test_creates_missing_records_and_updates_changed_ones(
    http: responses.RequestsMock, credentials: Callable[..., None]
) -> None:
    credentials(cloudflare_dns_token="token")
    http.get("https://ip.example", body="203.0.113.7\n")
    http.get(f"{CLOUDFLARE}/zones", json={"result": [{"id": "zone"}]})
    records = {
        "new.example.org": [],
        "old.example.org": [{"id": "old", "content": "198.51.100.1"}],
        "same.example.org": [{"id": "same", "content": "203.0.113.7"}],
    }
    for hostname, result in records.items():
        http.get(
            f"{CLOUDFLARE}/zones/zone/dns_records",
            match=[responses.matchers.query_param_matcher({"name": hostname, "type": "A"})],
            json={"result": result},
        )
    http.post(f"{CLOUDFLARE}/zones/zone/dns_records")
    http.put(f"{CLOUDFLARE}/zones/zone/dns_records/old")

    dyndns.apply(CONFIG)

    assert writes(http) == [
        ("POST", f"{CLOUDFLARE}/zones/zone/dns_records"),
        ("PUT", f"{CLOUDFLARE}/zones/zone/dns_records/old"),
    ]
    created = next(call for call in http.calls if call.request.method == "POST")
    assert json.loads(created.request.body) == {
        "type": "A",
        "name": "new.example.org",
        "content": "203.0.113.7",
        "proxied": False,
    }
    assert created.request.headers["Authorization"] == "Bearer token"
