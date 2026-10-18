import argparse
import html
import json
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote

import markdown
import yaml

FOLDERS = {
    "books": ("Books", ["author", "status", "pages", "tags"]),
    "games": ("Games", ["platform", "status", "hours", "tags"]),
    "cooking/recipes": (
        "Recipes",
        ["carbs_g", "servings", "absorption", "base", "time_min", "batch", "freezes", "tags"],
    ),
    "cooking/bases": (
        "Bases",
        ["base_type", "carb_load", "carbs_g", "portion_g", "gi", "absorption", "tags"],
    ),
    "cooking/components": ("Components", ["kind", "per", "carbs_g", "time_min", "tags"]),
}

LABELS = {
    "carbs_g": "Carbs g",
    "time_min": "Minutes",
    "base_type": "Base type",
    "carb_load": "Carb load",
    "portion_g": "Portion g",
    "gi": "GI",
}

WIKILINK = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]")
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)


@dataclass
class Note:
    name: str
    folder: str
    meta: dict[str, Any]
    body: str


def plain(value: Any) -> str:
    if isinstance(value, list):
        return " ".join(map(plain, value))
    return WIKILINK.sub(lambda m: m[2] or m[1], str(value))


def read_note(path: Path, folder: str) -> Note:
    text = path.read_text(encoding="utf-8")
    match = FRONTMATTER.match(text)
    meta, body = (yaml.safe_load(match[1]) or {}, match[2]) if match else ({}, text)
    return Note(path.stem, folder, meta, body)


class Site:
    def __init__(self, notes: list[Note], base: str):
        self.notes = {note.name: note for note in notes}
        self.base = base.rstrip("/")

    def note_url(self, name: str) -> str:
        return f"{self.base}/notes/{quote(name)}.html"

    def folder_url(self, folder: str) -> str:
        return f"{self.base}/{folder}/"

    def wikilink(self, target: str, label: str | None = None) -> str:
        target = target.strip()
        text = html.escape(label or target)
        if target in self.notes:
            return f'<a href="{self.note_url(target)}">{text}</a>'
        return f'<span class="missing">{text}</span>'

    def inline(self, value: Any) -> str:
        if isinstance(value, list):
            return ", ".join(self.inline(item) for item in value)
        if isinstance(value, bool):
            return "yes" if value else "no"
        text = str(value)
        if match := WIKILINK.fullmatch(text):
            return self.wikilink(match[1], match[2])
        return html.escape(text)

    def page(self, title: str, content: str, crumbs: tuple[tuple[str, str], ...] = ()) -> str:
        trail = "".join(f'<a href="{url}">{html.escape(label)}</a> / ' for label, url in crumbs)
        return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="{self.base}/style.css">
<script src="{self.base}/filter.js" defer></script>
</head>
<body>
<nav>{trail}</nav>
<main>
<h1>{html.escape(title)}</h1>
{content}
</main>
</body>
</html>
"""

    def render_body(self, body: str) -> str:
        # Resolved first: the pipe in [[Target|label]] would otherwise split a Markdown table cell.
        linked = WIKILINK.sub(lambda m: self.wikilink(m[1], m[2]), body)
        return markdown.markdown(linked, extensions=["tables", "fenced_code", "sane_lists"])

    def note_page(self, note: Note) -> str:
        label, _ = FOLDERS[note.folder]
        facts = "".join(
            f"<dt>{html.escape(LABELS.get(key, key.replace('_', ' ').capitalize()))}</dt>"
            f"<dd>{self.inline(value)}</dd>"
            for key, value in note.meta.items()
        )
        content = (f'<dl class="facts">{facts}</dl>' if facts else "") + self.render_body(note.body)
        return self.page(
            note.name, content, (("Lists", f"{self.base}/"), (label, self.folder_url(note.folder)))
        )

    def folder_page(self, folder: str, notes: list[Note]) -> str:
        label, columns = FOLDERS[folder]
        head = "".join(
            f'<th data-sort="{i + 1}">{html.escape(LABELS.get(c, c.replace("_", " ").capitalize()))}</th>'
            for i, c in enumerate(columns)
        )
        rows = []
        for note in sorted(notes, key=lambda n: n.name.casefold()):
            cells = "".join(
                f'<td data-value="{html.escape(json.dumps(note.meta.get(c, "")), quote=True)}">'
                f"{self.inline(note.meta[c]) if c in note.meta else ''}</td>"
                for c in columns
            )
            haystack = " ".join([note.name, *map(plain, note.meta.values())]).casefold()
            rows.append(
                f'<tr data-search="{html.escape(haystack, quote=True)}">'
                f'<td><a href="{self.note_url(note.name)}">{html.escape(note.name)}</a></td>{cells}</tr>'
            )
        content = (
            '<input type="search" class="filter" placeholder="Filter by name, tag or value" autofocus>'
            '<div class="scroll"><table class="list">'
            f'<thead><tr><th data-sort="0">Name</th>{head}</tr></thead>'
            f"<tbody>{''.join(rows)}</tbody></table></div>"
        )
        return self.page(label, content, (("Lists", f"{self.base}/"),))

    def index_page(self, by_folder: dict[str, list[Note]]) -> str:
        items = "".join(
            f'<li><a href="{self.folder_url(folder)}">{html.escape(FOLDERS[folder][0])}</a>'
            f' <span class="count">{len(notes)}</span></li>'
            for folder, notes in by_folder.items()
        )
        return self.page("Lists", f'<ul class="folders">{items}</ul>')


def render(vault: Path, out: Path, base: str, assets: Path) -> None:
    by_folder = {
        folder: [read_note(path, folder) for path in sorted((vault / folder).glob("*.md"))]
        for folder in FOLDERS
        if (vault / folder).is_dir()
    }
    by_folder = {folder: notes for folder, notes in by_folder.items() if notes}
    site = Site([note for notes in by_folder.values() for note in notes], base)

    (out / "notes").mkdir(parents=True, exist_ok=True)
    for asset in assets.iterdir():
        shutil.copy(asset, out / asset.name)
    (out / "index.html").write_text(site.index_page(by_folder), encoding="utf-8")
    for folder, notes in by_folder.items():
        (out / folder).mkdir(parents=True, exist_ok=True)
        (out / folder / "index.html").write_text(site.folder_page(folder, notes), encoding="utf-8")
        for note in notes:
            (out / "notes" / f"{note.name}.html").write_text(site.note_page(note), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the lists vault as a read-only site")
    parser.add_argument("vault", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--base", default="", help="URL path the site is served under, like /apps/lists")
    parser.add_argument("--assets", type=Path, default=Path(__file__).parent / "assets")
    args = parser.parse_args()
    render(args.vault, args.out, args.base, args.assets)


if __name__ == "__main__":
    main()
