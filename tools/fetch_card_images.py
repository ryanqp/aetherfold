#!/usr/bin/env python3
"""Download Scryfall images for Aetherfold's current table cards into D: cache."""
from __future__ import annotations

import json
import urllib.request
from pathlib import Path

DATA_DIR = Path(r"D:\AetherfoldData\scryfall")
IMAGE_DIR = DATA_DIR / "images"
CATALOG = DATA_DIR / "catalog.jsonl"
USER_AGENT = "Aetherfold/1.0 (Godot MTG companion; card art cache)"

NAMES = [
    "Krenko, Mob Boss",
    "Talrand, Sky Summoner",
    "Muxus, Goblin Grandee",
    "Forgotten Cave",
    "Goblin Ringleader",
    "Dragon Fodder",
    "Conspicuous Snoop",
    "Pashalik Mons",
    "Mountain",
    "Island",
    "Opt",
    "Ponder",
    "Unsummon",
    "Counterspell",
    "Cancel",
]


def request(url: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})


def load_catalog() -> dict[str, dict]:
    by_name: dict[str, dict] = {}
    with CATALOG.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            card = json.loads(line)
            name = (card.get("name") or "").strip().lower()
            if not name:
                continue
            existing = by_name.get(name)
            if existing is None:
                by_name[name] = card
                continue
            score = 0
            if (card.get("type_line") or "").startswith("Basic Land"):
                score += 8
            if card.get("commander_legal"):
                score += 5
            if (card.get("layout") or "") == "normal":
                score += 2
            old = 0
            if (existing.get("type_line") or "").startswith("Basic Land"):
                old += 8
            if existing.get("commander_legal"):
                old += 5
            if (existing.get("layout") or "") == "normal":
                old += 2
            if score > old:
                by_name[name] = card
    return by_name


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(request(url), timeout=60) as resp, dest.open("wb") as out:
        out.write(resp.read())


def main() -> int:
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    catalog = load_catalog()
    for name in NAMES:
        card = catalog.get(name.lower())
        if not card:
            print(f"MISSING {name}")
            continue
        cid = card.get("id")
        images = card.get("images") or {}
        for kind in ("small", "normal"):
            url = images.get(kind)
            if not url:
                print(f"NO {kind} URL for {name}")
                continue
            ext = ".jpg"
            dest = IMAGE_DIR / f"{cid}_{kind}{ext}"
            if dest.exists() and dest.stat().st_size > 0:
                print(f"HAVE {dest.name}")
                continue
            print(f"GET {name} {kind} -> {dest.name}")
            download(url, dest)
            print(f"  {dest.stat().st_size} bytes")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
