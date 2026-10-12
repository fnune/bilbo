from typing import Any

import requests

from .api import Api, credential, wait_until_up


def apply(config: dict[str, Any]) -> None:
    url = config["internalUrl"]
    password = credential("frigate-admin-password")
    wait_until_up(f"{url}/version")

    login = requests.post(f"{url}/login", json={"user": "admin", "password": password}, timeout=30)
    if not login.ok:
        Api(url).put("/users/admin/password", json={"password": password})
