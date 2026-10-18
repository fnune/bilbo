import json
from collections.abc import Callable
from datetime import date
from pathlib import Path

import pytest
import responses

from bilbo_tools import papra_dates

from .conftest import writes

API = "http://papra/api"
DOCUMENTS = f"{API}/organizations/org/documents"


def document(id: str, name: str, document_date: str | None = None) -> dict[str, str | None]:
    return {"id": id, "name": name, "documentDate": document_date}


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("2016-08-26 store2be - Employment contract.pdf", date(2016, 8, 26)),
        ("2026-09-03_Vertragsinformationen_Tagesgeldkonto.pdf", date(2026, 9, 3)),
        ("DOC-20260630-WA0001..pdf", date(2026, 6, 30)),
        ("Addendum (2023-10-15) - FA.pdf", date(2023, 10, 15)),
        ("Amazon.de - Order 306-9042199-7627507.html", None),
        ("2024-02-11_pb1705498610851433001469934843.pdf", date(2024, 2, 11)),
        ("Steuerpflichtiger-Einkommensteuer2024-Voransicht.pdf", None),
        ("2023-02-30 impossible.pdf", None),
    ],
)
def test_reads_dates_in_names(name: str, expected: date | None) -> None:
    assert papra_dates.date_in_name(name) == expected


def test_dates_undated_documents_from_their_names_then_their_text(
    http: responses.RequestsMock,
    credentials: Callable[..., None],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    credentials(papra_api_key="papra", anthropic_api_key="anthropic")
    asked_file = tmp_path / "asked"
    asked_file.write_text("doc_asked_before")
    model_answers = {"Letter.pdf": date(2019, 9, 2), "Passport.pdf": None}
    monkeypatch.setattr(
        papra_dates, "date_in_content", lambda _client, _model, name, _content: model_answers[name]
    )
    http.get(f"{API}/organizations", json={"organizations": [{"id": "org"}]})
    http.get(
        DOCUMENTS,
        json={
            "documents": [
                document("doc_named", "2016-08-26 store2be - Employment contract.pdf"),
                document("doc_dated", "Already dated.pdf", "2020-01-01T12:00:00.000Z"),
                document("doc_letter", "Letter.pdf"),
                document("doc_passport", "Passport.pdf"),
                document("doc_pending", "Not extracted yet.pdf"),
                document("doc_asked_before", "Undatable.pdf"),
            ]
        },
    )
    http.get(f"{DOCUMENTS}/doc_letter", json={"document": {"content": "Berlin, 02.09.2019"}})
    http.get(f"{DOCUMENTS}/doc_passport", json={"document": {"content": "PASSPORT"}})
    http.get(f"{DOCUMENTS}/doc_pending", json={"document": {"content": ""}})
    http.patch(f"{DOCUMENTS}/doc_named")
    http.patch(f"{DOCUMENTS}/doc_letter")

    papra_dates.apply({"url": "http://papra", "model": "model", "askedFile": str(asked_file)})

    assert writes(http) == [("PATCH", f"{DOCUMENTS}/doc_named"), ("PATCH", f"{DOCUMENTS}/doc_letter")]
    patches = [json.loads(call.request.body) for call in http.calls if call.request.method == "PATCH"]
    assert patches == [
        {"documentDate": "2016-08-26T12:00:00.000Z"},
        {"documentDate": "2019-09-02T12:00:00.000Z"},
    ]
    assert http.calls[0].request.headers["Authorization"] == "Bearer papra"
    assert asked_file.read_text().split() == ["doc_asked_before", "doc_letter", "doc_passport"]
