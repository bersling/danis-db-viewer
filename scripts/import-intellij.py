#!/usr/bin/env python3
"""Import IntelliJ data sources into Dani's DB Viewer.

Usage: import-intellij.py <path-to-.idea-dir> [...]

Parses .idea/dataSources.xml (+ dataSources.local.xml for usernames) and merges
the connections into ~/Library/Application Support/DanisDBViewer/connections.json.
IntelliJ UUIDs are kept as connection ids, so re-running updates instead of
duplicating. Passwords are NOT imported (they live in IntelliJ's keychain) —
enter them once in the app; they'll be stored in its own keychain entry.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

STORE = Path.home() / "Library/Application Support/DanisDBViewer/connections.json"


def parse_jdbc(url):
    m = re.match(r"jdbc:(mysql|postgresql|sqlite):(?://)?([^/?]*)(?:/([^?]*))?", url or "")
    if not m:
        return None
    kind = {"mysql": "mysql", "postgresql": "postgres", "sqlite": "sqlite"}[m.group(1)]
    if kind == "sqlite":
        return {"kind": kind, "filePath": m.group(2) + ("/" + m.group(3) if m.group(3) else "")}
    hostport = m.group(2)
    host, _, port = hostport.partition(":")
    default_port = 3306 if kind == "mysql" else 5432
    return {
        "kind": kind,
        "host": host or "localhost",
        "port": int(port) if port else default_port,
        "database": (m.group(3) or "").strip(),
    }


def import_idea(idea_dir, existing):
    ds_file = Path(idea_dir) / "dataSources.xml"
    if not ds_file.exists():
        print(f"skip (no dataSources.xml): {idea_dir}")
        return 0

    users = {}
    local = Path(idea_dir) / "dataSources.local.xml"
    if local.exists():
        for ds in ET.parse(local).getroot().iter("data-source"):
            uuid = ds.get("uuid")
            user = ds.find("user-name")
            if uuid and user is not None and user.text:
                users[uuid] = user.text

    count = 0
    for ds in ET.parse(ds_file).getroot().iter("data-source"):
        uuid, name = ds.get("uuid"), ds.get("name")
        url_el = ds.find("jdbc-url")
        parsed = parse_jdbc(url_el.text if url_el is not None else None)
        if not uuid or not parsed:
            print(f"  ! could not parse: {name}")
            continue
        entry = {
            "id": uuid.upper(),
            "name": name,
            "kind": parsed["kind"],
            "host": parsed.get("host", "localhost"),
            "port": parsed.get("port", 0),
            "user": users.get(uuid, ""),
            "database": parsed.get("database", ""),
            "filePath": parsed.get("filePath", ""),
            "color": "none",
            "comment": "imported from IntelliJ",
        }
        existing[entry["id"]] = {**existing.get(entry["id"], {}), **entry}
        count += 1
        print(f"  + {name} ({entry['kind']}) {entry.get('host','')}:{entry.get('port','')}"
              f"{'/' + entry['database'] if entry['database'] else ''} user={entry['user'] or '-'}")
    return count


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    current = []
    if STORE.exists():
        current = json.loads(STORE.read_text())
    by_id = {c["id"]: c for c in current}

    total = 0
    for idea in sys.argv[1:]:
        print(f"importing {idea}")
        total += import_idea(idea, by_id)

    merged = sorted(by_id.values(), key=lambda c: c["name"].lower())
    STORE.parent.mkdir(parents=True, exist_ok=True)
    STORE.write_text(json.dumps(merged, indent=2, sort_keys=True))
    print(f"\n{total} imported/updated, {len(merged)} total → {STORE}")


if __name__ == "__main__":
    main()
