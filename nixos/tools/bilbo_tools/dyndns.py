from typing import Any

import requests

from .api import Api, credential

CLOUDFLARE = "https://api.cloudflare.com/client/v4"


def apply(config: dict[str, Any]) -> None:
    address = requests.get(config["addressUrl"], timeout=30).text.strip()
    cloudflare = Api(CLOUDFLARE, {"Authorization": f"Bearer {credential('cloudflare-dns-token')}"})
    zone = cloudflare.get("/zones", params={"name": config["zone"]})["result"][0]["id"]

    for hostname in config["hostnames"]:
        record = {"type": "A", "name": hostname, "content": address, "proxied": False}
        existing = cloudflare.get(f"/zones/{zone}/dns_records", params={"name": hostname, "type": "A"})[
            "result"
        ]
        if not existing:
            cloudflare.post(f"/zones/{zone}/dns_records", json=record)
        elif existing[0]["content"] != address:
            cloudflare.put(f"/zones/{zone}/dns_records/{existing[0]['id']}", json=record)
