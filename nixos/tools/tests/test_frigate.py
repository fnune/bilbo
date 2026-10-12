from collections.abc import Callable

import responses

from bilbo_tools import frigate

from .conftest import writes

URL = "http://frigate/api"


def run(http: responses.RequestsMock, credentials: Callable[..., None], login_status: int) -> None:
    credentials(frigate_admin_password="correct horse battery")
    http.get(f"{URL}/version")
    http.post(f"{URL}/login", status=login_status)
    http.put(f"{URL}/users/admin/password")
    frigate.apply({"internalUrl": URL})


def test_leaves_a_working_password_alone(
    http: responses.RequestsMock, credentials: Callable[..., None]
) -> None:
    run(http, credentials, login_status=200)
    assert writes(http) == [("POST", f"{URL}/login")]


def test_sets_the_password_when_login_fails(
    http: responses.RequestsMock, credentials: Callable[..., None]
) -> None:
    run(http, credentials, login_status=401)
    assert ("PUT", f"{URL}/users/admin/password") in writes(http)
