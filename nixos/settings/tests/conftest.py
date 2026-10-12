from collections.abc import Callable, Iterator
from pathlib import Path

import pytest
import responses


@pytest.fixture(autouse=True)
def no_waiting(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("bilbo_settings.api.time.sleep", lambda _: None)


@pytest.fixture
def credentials(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Callable[..., None]:
    directory = tmp_path / "credentials"
    directory.mkdir()
    monkeypatch.setenv("CREDENTIALS_DIRECTORY", str(directory))

    def write(**values: str) -> None:
        for name, value in values.items():
            (directory / name.replace("_", "-")).write_text(f"{value}\n")

    return write


@pytest.fixture
def http() -> Iterator[responses.RequestsMock]:
    with responses.RequestsMock(assert_all_requests_are_fired=False) as mock:
        yield mock


def writes(http: responses.RequestsMock) -> list[tuple[str, str]]:
    return [
        (call.request.method, call.request.url.split("?")[0])
        for call in http.calls
        if call.request.method != "GET"
    ]
