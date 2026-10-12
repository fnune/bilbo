import subprocess
from typing import Any

from .api import wait_until_up


def apply(config: dict[str, Any]) -> None:
    for url in config["waitFor"]:
        wait_until_up(url)
    subprocess.run([config["systemctl"], "start", "recyclarr.service"], check=True)
