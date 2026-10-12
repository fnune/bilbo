import pytest
import responses

from bilbo_tools.api import Api, has, wait_until_up


def test_waits_through_server_errors(http: responses.RequestsMock) -> None:
    http.get("http://app/ping", status=503)
    http.get("http://app/ping", status=401)
    wait_until_up("http://app/ping")
    assert len(http.calls) == 2


def test_gives_up_when_the_app_never_answers(http: responses.RequestsMock) -> None:
    http.get("http://app/ping", status=503)
    with pytest.raises(TimeoutError):
        wait_until_up("http://app/ping", attempts=3)


def test_errors_carry_the_app_message(http: responses.RequestsMock) -> None:
    http.post("http://app/thing", status=400, body="apiKey is read-only")
    with pytest.raises(RuntimeError, match="apiKey is read-only"):
        Api("http://app").post("/thing", json={})


def test_has_matches_every_given_field() -> None:
    items = [{"name": "a", "kind": "x"}, {"name": "b", "kind": "y"}]
    assert has(items, name="b", kind="y")
    assert not has(items, name="b", kind="x")
