import argparse
import json
from pathlib import Path

from . import arrs, bazarr, beszel, dyndns, frigate, jellyfin, recyclarr

APPLY = {
    "arr": arrs.apply,
    "bazarr": bazarr.apply,
    "beszel": beszel.apply,
    "dyndns": dyndns.apply,
    "frigate": frigate.apply,
    "jellyfin": jellyfin.apply,
    "recyclarr": recyclarr.apply,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Bilbo's maintenance tools.")
    parser.add_argument("app", choices=APPLY)
    parser.add_argument("config", type=Path)
    arguments = parser.parse_args()
    APPLY[arguments.app](json.loads(arguments.config.read_text()))


if __name__ == "__main__":
    main()
