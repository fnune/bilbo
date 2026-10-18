import json
import os
import subprocess
from collections.abc import Callable, Sequence
from datetime import datetime
from pathlib import Path
from typing import Any

import pytest

from bilbo_tools import restore


class FakeRun:
    def __init__(self, outputs: dict[str, str | bytes]) -> None:
        self.outputs = outputs
        self.calls: list[list[str]] = []

    def __call__(self, arguments: Sequence[str], **_: Any) -> subprocess.CompletedProcess:
        self.calls.append(list(arguments))
        key = next((key for key in self.outputs if key in " ".join(arguments)), None)
        return subprocess.CompletedProcess(arguments, 0, stdout=self.outputs.get(key, "") if key else "")


@pytest.fixture
def secrets(credentials: Callable[..., None], tmp_path: Path) -> None:
    credentials(borg_passphrase="secret", borg_s3_bucket_name="bucket", rclone_conf="[remote]")


BACKED_UP_AT = "2026-10-12T11:53:29.123456"


def write_original(root: Path, content: bytes, modified: str = BACKED_UP_AT) -> None:
    original = root / "photos" / "a.jpg"
    original.parent.mkdir(exist_ok=True)
    original.write_bytes(content)
    timestamp = datetime.fromisoformat(modified).timestamp()
    os.utime(original, (timestamp, timestamp))


def local_config(**overrides: Any) -> dict[str, Any]:
    return {
        "borg": "borg",
        "repository": "/repo",
        "lockWaitSeconds": 60,
        "samplePath": "photos",
        "maxFileBytes": 1000,
        "notify": "notify",
        "root": "/",
        "sqliteSnapshotPath": "snapshots",
        "sqlite": "sqlite3",
    } | overrides


def test_local_check_verifies_the_repository_and_compares_restored_files(
    secrets: None, tmp_path: Path
) -> None:
    write_original(tmp_path, b"pixels")
    run = FakeRun(
        {
            "--short": "archive-1\n",
            "{type} {path}": "- snapshots/var/lib/app/app.db\nd snapshots/var/lib/app\n",
            "--format": f"- 6 {BACKED_UP_AT} photos/a.jpg\n- 5000 {BACKED_UP_AT} photos/huge.mov\n"
            f"d 0 {BACKED_UP_AT} photos\n",
            "snapshots/": b"SQLite format 3",
            "extract": b"pixels",
            "integrity_check": "ok\n",
        }
    )

    restore.check_local(local_config(root=str(tmp_path)), run=run)

    commands = [call[0] if call[0] == "sqlite3" else call[1] for call in run.calls]
    assert commands == [
        "check",
        "list",
        "list",
        "extract",
        "list",
        "extract",
        "sqlite3",
        "Local backup verified",
    ]
    assert run.calls[0][:3] == ["borg", "check", "--verify-data"]
    assert run.calls[3][-1] == "photos/a.jpg"
    assert run.calls[5][-1] == "snapshots/var/lib/app/app.db"
    assert run.calls[6][-1] == "PRAGMA integrity_check"


def test_local_check_fails_when_a_sqlite_snapshot_is_corrupt(secrets: None, tmp_path: Path) -> None:
    write_original(tmp_path, b"pixels")
    run = FakeRun(
        {
            "--short": "archive-1\n",
            "{type} {path}": "- snapshots/var/lib/app/app.db\n",
            "--format": f"- 6 {BACKED_UP_AT} photos/a.jpg\n",
            "snapshots/": b"garbage",
            "extract": b"pixels",
            "integrity_check": "*** in database main ***\nPage 2 is never used\n",
        }
    )

    with pytest.raises(ValueError, match="integrity_check"):
        restore.check_local(local_config(root=str(tmp_path)), run=run)
    assert not any("verified" in " ".join(call) for call in run.calls)


def test_local_check_fails_when_a_restored_file_differs(secrets: None, tmp_path: Path) -> None:
    write_original(tmp_path, b"pixels")
    run = FakeRun(
        {"--short": "archive-1\n", "--format": f"- 6 {BACKED_UP_AT} photos/a.jpg\n", "extract": b"broken"}
    )

    with pytest.raises(ValueError, match="differs"):
        restore.check_local(local_config(root=str(tmp_path)), run=run)
    assert not any("verified" in " ".join(call) for call in run.calls)


def test_local_check_skips_files_changed_since_the_backup(secrets: None, tmp_path: Path) -> None:
    write_original(tmp_path, b"rewritten", modified="2026-10-12T15:00:00")
    run = FakeRun(
        {"--short": "archive-1\n", "--format": f"- 6 {BACKED_UP_AT} photos/a.jpg\n", "extract": b"pixels"}
    )

    with pytest.raises(LookupError, match="could be compared"):
        restore.check_local(local_config(root=str(tmp_path)), run=run)
    assert not any(call[1] == "extract" for call in run.calls)


def test_the_remote_sample_stays_within_budget() -> None:
    files = [{"Path": f"data/{index}", "Size": 400} for index in range(10)]
    sample = restore.choose_sample(files, budget_bytes=1000)
    assert len(sample) == 2
    assert len(set(sample)) == 2


def test_remote_start_thaws_the_sample_in_bulk(secrets: None, tmp_path: Path) -> None:
    listing = json.dumps([{"Path": "data/0/1", "Size": 10}, {"Path": "data/0/2", "Size": 10}])
    run = FakeRun({"lsjson": listing})
    config = {
        "rclone": "rclone",
        "remote": "glacier",
        "prefix": "mirrored",
        "sampleBytes": 15,
        "sampleFile": str(tmp_path / "sample"),
        "availableDays": 7,
    }

    restore.start_remote(config, run=run)

    restore_call = run.calls[-1]
    assert "restore" in restore_call
    assert "priority=Bulk" in restore_call
    assert restore_call[-1] == "glacier:bucket/mirrored"
    assert len((tmp_path / "sample").read_text().split()) == 1


def test_remote_check_compares_only_files_still_in_the_local_repository(
    secrets: None, tmp_path: Path
) -> None:
    repository = tmp_path / "repo"
    (repository / "data" / "0").mkdir(parents=True)
    (repository / "data" / "0" / "1").write_bytes(b"segment")
    sample = tmp_path / "sample"
    sample.write_text("data/0/1\ndata/0/compacted\n")
    run = FakeRun({})
    config = {
        "rclone": "rclone",
        "remote": "glacier",
        "prefix": "mirrored",
        "sampleFile": str(sample),
        "repository": str(repository),
        "notify": "notify",
    }

    restore.check_remote(config, run=run)

    check_call = run.calls[0]
    assert {"check", "--one-way", "--download"} <= set(check_call)
    assert sample.with_suffix(".comparable").read_text() == "data/0/1\n"
    assert run.calls[-1][1] == "Off-site backup verified"
