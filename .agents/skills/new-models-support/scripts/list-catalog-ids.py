#!/usr/bin/env python3
"""List ModelCatalog Record IDs from Jin Swift sources.

Usage (repo root or anywhere):
  python3 .agents/skills/new-models-support/scripts/list-catalog-ids.py
  python3 .../list-catalog-ids.py --provider openai
  python3 .../list-catalog-ids.py --seeded
  python3 .../list-catalog-ids.py --full
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

RECORD_RE = re.compile(
    r'Record\(\s*id:\s*"(?P<id>[^"]+)"'
    r"(?P<body>.*?)"
    r"isFullySupported:\s*(?P<full>true|false)"
    r",\s*isSeeded:\s*(?P<seeded>true|false)\s*\)",
    re.S,
)

# RunInfra wraps Record() in a local `hosted(...)` helper that always sets
# isFullySupported: true and only exposes isSeeded at the call site.
HOSTED_RE = re.compile(
    r'hosted\(\s*id:\s*"(?P<id>[^"]+)"'
    r"(?P<body>.*?)"
    r"isSeeded:\s*(?P<seeded>true|false)\s*\)",
    re.S,
)

TABLE_RE = re.compile(
    r"static let (?P<table>\w+Records)\b",
)

DISPLAY_RE = re.compile(r'displayName:\s*"(?P<name>[^"]+)"')


def repo_root_from(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "Package.swift").exists() and (
            candidate / "Sources" / "Domain"
        ).exists():
            return candidate
    raise SystemExit("Could not find Jin repo root (Package.swift + Sources/Domain)")


def catalog_files(root: Path) -> list[Path]:
    domain = root / "Sources" / "Domain"
    files = sorted(domain.glob("ModelCatalogRecords*.swift"))
    if not files:
        raise SystemExit(f"No ModelCatalogRecords*.swift under {domain}")
    return files


def parse_file(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    rows: list[dict] = []
    # Walk the file so each record inherits the nearest preceding `static let *Records`.
    markers = [(m.start(), m.group("table")) for m in TABLE_RE.finditer(text)]
    found: list[tuple[int, dict]] = []
    for rec in RECORD_RE.finditer(text):
        found.append(
            (
                rec.start(),
                {
                    "id": rec.group("id"),
                    "body": rec.group("body"),
                    "full": rec.group("full") == "true",
                    "seeded": rec.group("seeded") == "true",
                },
            )
        )
    for rec in HOSTED_RE.finditer(text):
        found.append(
            (
                rec.start(),
                {
                    "id": rec.group("id"),
                    "body": rec.group("body"),
                    "full": True,
                    "seeded": rec.group("seeded") == "true",
                },
            )
        )
    found.sort(key=lambda item: item[0])

    table = None
    marker_idx = 0
    for start, rec in found:
        while marker_idx < len(markers) and markers[marker_idx][0] < start:
            table = markers[marker_idx][1]
            marker_idx += 1
        display = None
        dm = DISPLAY_RE.search(rec["body"])
        if dm:
            display = dm.group("name")
        rows.append(
            {
                "file": path.name,
                "table": table or "unknownRecords",
                "id": rec["id"],
                "display": display or "",
                "full": rec["full"],
                "seeded": rec["seeded"],
            }
        )
    return rows


def table_to_provider(table: str) -> str:
    if table.endswith("Records"):
        return table[: -len("Records")]
    return table


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--provider",
        help="Substring match against record table name (e.g. openai, anthropic, openRouter)",
    )
    parser.add_argument("--seeded", action="store_true", help="Only isSeeded: true")
    parser.add_argument("--full", action="store_true", help="Only isFullySupported: true")
    parser.add_argument(
        "--tsv",
        action="store_true",
        help="Machine-readable: provider\tid\tfull\tseeded\tdisplay\tfile",
    )
    args = parser.parse_args()

    root = repo_root_from(Path(__file__).resolve())
    rows: list[dict] = []
    for path in catalog_files(root):
        rows.extend(parse_file(path))

    if args.provider:
        needle = args.provider.lower().replace("-", "").replace("_", "")
        rows = [
            r
            for r in rows
            if needle in r["table"].lower().replace("_", "")
            or needle in table_to_provider(r["table"]).lower()
        ]
    if args.seeded:
        rows = [r for r in rows if r["seeded"]]
    if args.full:
        rows = [r for r in rows if r["full"]]

    if args.tsv:
        for r in rows:
            print(
                "\t".join(
                    [
                        table_to_provider(r["table"]),
                        r["id"],
                        "full" if r["full"] else "catalog",
                        "seeded" if r["seeded"] else "unseeded",
                        r["display"].replace("\t", " "),
                        r["file"],
                    ]
                )
            )
        return 0

    current_table = None
    for r in rows:
        if r["table"] != current_table:
            current_table = r["table"]
            print(f"\n## {current_table}  ({r['file']})")
        flags = []
        flags.append("✦" if r["full"] else "·")
        flags.append("seed" if r["seeded"] else "    ")
        name = f"  {r['display']}" if r["display"] else ""
        print(f"  {''.join(flags)}  {r['id']}{name}")

    print(f"\n# {len(rows)} records", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
