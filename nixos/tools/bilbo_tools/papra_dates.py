import re
from collections.abc import Iterator
from datetime import date
from pathlib import Path
from typing import Any

import anthropic
from pydantic import BaseModel

from .api import Api, credential

DATE_IN_NAME = re.compile(r"(?<!\d)((?:19|20)\d{2})-?(0[1-9]|1[0-2])-?(0[1-9]|[12]\d|3[01])(?!\d)")
PAGE_SIZE = 100
CONTENT_CHARACTERS = 20_000
PROMPT = """This is a document from a personal archive. Give the date it was issued or signed, such as \
a letter, invoice, contract or certificate date, or the last day of the period a payslip or statement \
covers. Answer null when the text has no such date. Ignore birth dates and expiry dates.

File name: {name}

{content}"""


class DocumentDate(BaseModel):
    date: date | None


def date_in_name(name: str) -> date | None:
    for match in DATE_IN_NAME.finditer(name):
        try:
            return date(*map(int, match.groups()))
        except ValueError:
            continue
    return None


def date_in_content(client: anthropic.Anthropic, model: str, name: str, content: str) -> date | None:
    prompt = PROMPT.format(name=name, content=content[:CONTENT_CHARACTERS])
    response = client.messages.parse(
        model=model,
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
        output_format=DocumentDate,
    )
    return response.parsed_output.date if response.parsed_output else None


def undated_documents(papra: Api, documents_path: str) -> Iterator[dict[str, Any]]:
    page = 0
    while True:
        documents = papra.get(documents_path, params={"pageIndex": page, "pageSize": PAGE_SIZE})["documents"]
        yield from (document for document in documents if document["documentDate"] is None)
        if len(documents) < PAGE_SIZE:
            return
        page += 1


def apply(config: dict[str, Any]) -> None:
    papra = Api(f"{config['url']}/api", {"Authorization": f"Bearer {credential('papra-api-key')}"})
    client = anthropic.Anthropic(api_key=credential("anthropic-api-key"))
    asked_file = Path(config["askedFile"])
    asked = set(asked_file.read_text().split()) if asked_file.exists() else set()

    for organization in papra.get("/organizations")["organizations"]:
        documents_path = f"/organizations/{organization['id']}/documents"
        for document in undated_documents(papra, documents_path):
            document_path = f"{documents_path}/{document['id']}"
            found = date_in_name(document["name"])
            if found is None and document["id"] not in asked:
                content = papra.get(document_path)["document"]["content"]
                if not content:
                    continue
                found = date_in_content(client, config["model"], document["name"], content)
                asked.add(document["id"])
                asked_file.write_text("\n".join(sorted(asked)))
            print(f"{found or 'no date'}\t{document['name']}", flush=True)
            if found:
                papra.patch(document_path, json={"documentDate": f"{found.isoformat()}T12:00:00.000Z"})
