import json
import os
import random
import subprocess
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

from .api import credential

Run = Callable[..., subprocess.CompletedProcess]

FILES_TO_COMPARE = 3


def run_command(arguments: Sequence[str], **kwargs: Any) -> subprocess.CompletedProcess:
    return subprocess.run(arguments, check=True, **kwargs)


def borg_environment() -> dict[str, str]:
    return os.environ | {"BORG_PASSPHRASE": credential("borg-passphrase")}


def check_local(config: dict[str, Any], run: Run = run_command) -> None:
    borg, repository = config["borg"], config["repository"]
    environment = borg_environment()
    lock_wait = ["--lock-wait", str(config["lockWaitSeconds"])]

    run([borg, "check", "--verify-data", *lock_wait, repository], env=environment)

    archive = run(
        [borg, "list", "--short", "--last", "1", *lock_wait, repository],
        env=environment,
        capture_output=True,
        text=True,
    ).stdout.strip()
    listing = run(
        [
            borg,
            "list",
            "--format",
            "{type} {size} {path}{NL}",
            *lock_wait,
            f"{repository}::{archive}",
            config["samplePath"],
        ],
        env=environment,
        capture_output=True,
        text=True,
    ).stdout
    candidates = [
        path
        for kind, size, path in (line.split(" ", 2) for line in listing.splitlines())
        if kind == "-" and int(size) <= config["maxFileBytes"]
    ]

    compared = []
    for path in random.sample(candidates, len(candidates)):
        original = Path(config["root"]) / path
        if not original.is_file():
            continue
        restored = run(
            [borg, "extract", "--stdout", *lock_wait, f"{repository}::{archive}", path],
            env=environment,
            capture_output=True,
        ).stdout
        if restored != original.read_bytes():
            raise ValueError(f"{path} restored from {archive} differs from {original}")
        compared.append(path)
        if len(compared) == FILES_TO_COMPARE:
            break
    if not compared:
        raise LookupError(f"no file under {config['samplePath']} in {archive} could be compared")

    run(
        [
            config["notify"],
            "Local backup verified",
            f"borg check passed and {len(compared)} files restored from {archive} match.",
        ],
    )


def remote_path(config: dict[str, Any]) -> str:
    return f"{config['remote']}:{credential('borg-s3-bucket-name')}/{config['prefix']}"


def rclone(config: dict[str, Any], *arguments: str) -> list[str]:
    return [
        config["rclone"],
        "--config",
        str(Path(os.environ["CREDENTIALS_DIRECTORY"]) / "rclone-conf"),
        *arguments,
    ]


def choose_sample(files: list[dict[str, Any]], budget_bytes: int) -> list[str]:
    chosen, total = [], 0
    for file in random.sample(files, len(files)):
        if total + file["Size"] > budget_bytes:
            continue
        chosen.append(file["Path"])
        total += file["Size"]
    return chosen


def start_remote(config: dict[str, Any], run: Run = run_command) -> None:
    listing = run(
        rclone(config, "lsjson", "--recursive", "--files-only", "--include", "data/**", remote_path(config)),
        capture_output=True,
        text=True,
    ).stdout
    sample = choose_sample(json.loads(listing), config["sampleBytes"])
    if not sample:
        raise LookupError("the remote repository has no data files to sample")

    sample_file = Path(config["sampleFile"])
    sample_file.write_text("".join(f"{path}\n" for path in sample))
    run(
        rclone(
            config,
            "backend",
            "restore",
            "-o",
            "priority=Bulk",
            "-o",
            f"lifetime={config['availableDays']}",
            "--files-from",
            str(sample_file),
            remote_path(config),
        ),
    )


def check_remote(config: dict[str, Any], run: Run = run_command) -> None:
    sample_file = Path(config["sampleFile"])
    repository = Path(config["repository"])
    still_local = [path for path in sample_file.read_text().split() if (repository / path).is_file()]
    if not still_local:
        raise LookupError(f"none of the files in {sample_file} are still in the local repository")

    comparable = sample_file.with_suffix(".comparable")
    comparable.write_text("".join(f"{path}\n" for path in still_local))
    run(
        rclone(
            config,
            "check",
            "--one-way",
            "--download",
            "--files-from",
            str(comparable),
            remote_path(config),
            str(repository),
        ),
    )
    run(
        [
            config["notify"],
            "Off-site backup verified",
            f"{len(still_local)} files thawed from Deep Archive match the local copy.",
        ],
    )
