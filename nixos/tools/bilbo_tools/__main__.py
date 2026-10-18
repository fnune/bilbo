import argparse
import json
from pathlib import Path

from . import arrs, bazarr, beszel, dyndns, frigate, jellyfin, papra_dates, recyclarr, restore

COMMANDS = {
    "arr": arrs.apply,
    "bazarr": bazarr.apply,
    "beszel": beszel.apply,
    "dyndns": dyndns.apply,
    "frigate": frigate.apply,
    "jellyfin": jellyfin.apply,
    "papra-dates": papra_dates.apply,
    "recyclarr": recyclarr.apply,
    "restore-check-local": restore.check_local,
    "restore-start-remote": restore.start_remote,
    "restore-check-remote": restore.check_remote,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Bilbo's maintenance tools.")
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("config", type=Path)
    arguments = parser.parse_args()
    COMMANDS[arguments.command](json.loads(arguments.config.read_text()))


if __name__ == "__main__":
    main()
