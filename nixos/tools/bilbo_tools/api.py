import os
import time
from pathlib import Path
from typing import Any

import requests


def credential(name: str) -> str:
    return (Path(os.environ["CREDENTIALS_DIRECTORY"]) / name).read_text().strip()


def wait_until_up(url: str, attempts: int = 60, delay_seconds: float = 2) -> None:
    for _ in range(attempts):
        try:
            if requests.get(url, timeout=5).status_code < 500:
                return
        except requests.ConnectionError:
            pass
        time.sleep(delay_seconds)
    raise TimeoutError(f"{url} did not answer within {attempts * delay_seconds:.0f} seconds")


def has(items: list[dict[str, Any]], **expected: Any) -> bool:
    return any(all(item.get(key) == value for key, value in expected.items()) for item in items)


class Api:
    def __init__(self, base_url: str, headers: dict[str, str] | None = None) -> None:
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update(headers or {})

    def request(self, method: str, path: str, attempts: int = 4, **kwargs: Any) -> Any:
        for attempt in range(attempts):
            response = self.session.request(method, self.base_url + path, timeout=120, **kwargs)
            if response.status_code < 500 or attempt == attempts - 1:
                break
            time.sleep(2**attempt)
        if not response.ok:
            raise RuntimeError(f"{method} {path} returned {response.status_code}: {response.text}")
        return response.json() if response.content else None

    def get(self, path: str, **kwargs: Any) -> Any:
        return self.request("GET", path, **kwargs)

    def post(self, path: str, **kwargs: Any) -> Any:
        return self.request("POST", path, **kwargs)

    def put(self, path: str, **kwargs: Any) -> Any:
        return self.request("PUT", path, **kwargs)

    def patch(self, path: str, **kwargs: Any) -> Any:
        return self.request("PATCH", path, **kwargs)

    def delete(self, path: str, **kwargs: Any) -> Any:
        return self.request("DELETE", path, **kwargs)
