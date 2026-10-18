import json
import os
import random
import subprocess
import tempfile
from collections.abc import Callable, Sequence
from datetime import datetime
from pathlib import Path
from typing import Any

from .api import credential

Run = Callable[..., subprocess.CompletedProcess]

FILES_TO_COMPARE = 3
MTIME_TOLERANCE_SECONDS = 0.001


def run_command(arguments: Sequence[str], **kwargs: Any) -> subprocess.CompletedProcess:
    return subprocess.run(arguments, check=True, **kwargs)


def borg_environment() -> dict[str, str]:
    return os.environ | {"BORG_PASSPHRASE": credential("borg-passphrase")}


def unchanged_since_backup(original: Path, archived_mtime: str) -> bool:
    if not original.is_file():
        return False
    archived = datetime.fromisoformat(archived_mtime).timestamp()
    return abs(original.stat().st_mtime - archived) < MTIME_TOLERANCE_SECONDS


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
            "{type} {size} {isomtime} {path}{NL}",
            *lock_wait,
            f"{repository}::{archive}",
            config["samplePath"],
        ],
        env=environment,
        capture_output=True,
        text=True,
    ).stdout
    candidates = [
        (path, mtime)
        for kind, size, mtime, path in (line.split(" ", 3) for line in listing.splitlines())
        if kind == "-" and int(size) <= config["maxFileBytes"]
    ]

    compared = []
    for path, mtime in random.sample(candidates, len(candidates)):
        original = Path(config["root"]) / path
        if not unchanged_since_backup(original, mtime):
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

    databases = check_sqlite_snapshots(config, archive, environment, lock_wait, run)

    run(
        [
            config["notify"],
            "Local backup verified",
            f"borg check passed, {len(compared)} files restored from {archive} match"
            f" and {databases} SQLite snapshots pass integrity_check.",
        ],
    )


def check_sqlite_snapshots(
    config: dict[str, Any], archive: str, environment: dict[str, str], lock_wait: list[str], run: Run
) -> int:
    borg, repository = config["borg"], config["repository"]
    listing = run(
        [
            borg,
            "list",
            "--format",
            "{type} {path}{NL}",
            *lock_wait,
            f"{repository}::{archive}",
            config["sqliteSnapshotPath"],
        ],
        env=environment,
        capture_output=True,
        text=True,
    ).stdout
    snapshots = [path for kind, path in (line.split(" ", 1) for line in listing.splitlines()) if kind == "-"]
    if not snapshots:
        raise LookupError(f"no SQLite snapshot under {config['sqliteSnapshotPath']} in {archive}")

    with tempfile.TemporaryDirectory() as directory:
        restored = Path(directory) / "restored.db"
        for path in snapshots:
            restored.write_bytes(
                run(
                    [borg, "extract", "--stdout", *lock_wait, f"{repository}::{archive}", path],
                    env=environment,
                    capture_output=True,
                ).stdout
            )
            result = run(
                [config["sqlite"], str(restored), "PRAGMA integrity_check"], capture_output=True, text=True
            ).stdout.strip()
            if result != "ok":
                raise ValueError(f"{path} in {archive} fails integrity_check: {result}")
    return len(snapshots)


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
