#!/usr/bin/env python3
"""Download Scryfall Oracle Cards and write a lean catalog for Aetherfold.

Stores data on D: so the Godot project on C: stays small. Does not download
card images — only metadata plus image URLs.
"""
from __future__ import annotations

import gzip
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(os.environ.get("AETHERFOLD_SCRYFALL_DIR", r"D:\AetherfoldData\scryfall"))
BULK_META_URL = "https://api.scryfall.com/bulk-data/oracle-cards"
USER_AGENT = "Aetherfold/1.0 (Godot MTG companion; local catalog build)"


def request(url: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})


def pick_image(card: dict) -> dict:
    uris = card.get("image_uris")
    if not uris:
        faces = card.get("card_faces") or []
        if faces:
            uris = faces[0].get("image_uris")
    if not isinstance(uris, dict):
        return {}
    out = {}
    for key in ("small", "normal", "large", "png", "art_crop"):
        if uris.get(key):
            out[key] = uris[key]
    return out


def face_names(card: dict) -> list[str]:
    names: list[str] = []
    for face in card.get("card_faces") or []:
        n = (face.get("name") or "").strip()
        if n and n not in names:
            names.append(n)
    return names


def lean_card(card: dict) -> dict:
    legalities = card.get("legalities") or {}
    return {
        "id": card.get("id") or "",
        "oracle_id": card.get("oracle_id") or "",
        "name": card.get("name") or "",
        "mana_cost": card.get("mana_cost") or "",
        "cmc": card.get("cmc") if card.get("cmc") is not None else 0,
        "type_line": card.get("type_line") or "",
        "oracle_text": card.get("oracle_text") or "",
        "colors": card.get("colors") or [],
        "color_identity": card.get("color_identity") or [],
        "keywords": card.get("keywords") or [],
        "power": card.get("power"),
        "toughness": card.get("toughness"),
        "loyalty": card.get("loyalty"),
        "layout": card.get("layout") or "normal",
        "set": card.get("set") or "",
        "set_name": card.get("set_name") or "",
        "collector_number": card.get("collector_number") or "",
        "rarity": card.get("rarity") or "",
        "commander_legal": legalities.get("commander") == "legal",
        "faces": face_names(card),
        "images": pick_image(card),
    }


def main() -> int:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Data dir: {DATA_DIR}", flush=True)

    print("Fetching bulk-data metadata...", flush=True)
    with urllib.request.urlopen(request(BULK_META_URL), timeout=60) as resp:
        bulk = json.loads(resp.read().decode("utf-8"))
    url = bulk["jsonl_download_uri"]
    updated = bulk.get("updated_at")
    compressed = int(bulk.get("compressed_size") or 0)
    gz_path = DATA_DIR / "oracle-cards.jsonl.gz"
    catalog_path = DATA_DIR / "catalog.jsonl"
    meta_path = DATA_DIR / "meta.json"

    print(f"Downloading {url}", flush=True)
    print(f"Compressed size: {compressed / (1024 * 1024):.1f} MB", flush=True)
    with urllib.request.urlopen(request(url), timeout=300) as resp, gz_path.open("wb") as out:
        copied = 0
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)
            copied += len(chunk)
            if copied % (8 * 1024 * 1024) < 1024 * 1024:
                print(f"  downloaded {copied / (1024 * 1024):.1f} MB", flush=True)
    actual = gz_path.stat().st_size
    print(f"Saved {gz_path} ({actual / (1024 * 1024):.1f} MB)", flush=True)

    count = 0
    print("Converting to lean catalog...", flush=True)
    with gzip.open(gz_path, "rt", encoding="utf-8") as src, catalog_path.open(
        "w", encoding="utf-8", newline="\n"
    ) as dst:
        for line in src:
            line = line.strip()
            if not line:
                continue
            card = json.loads(line)
            dst.write(json.dumps(lean_card(card), ensure_ascii=False, separators=(",", ":")) + "\n")
            count += 1
            if count % 5000 == 0:
                print(f"  {count} cards...", flush=True)

    catalog_size = catalog_path.stat().st_size
    meta = {
        "source": "scryfall",
        "bulk_type": "oracle_cards",
        "updated_at": updated,
        "downloaded_at": datetime.now(timezone.utc).isoformat(),
        "card_count": count,
        "compressed_bytes": actual,
        "catalog_bytes": catalog_size,
        "catalog_path": str(catalog_path),
        "download_uri": url,
    }
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"Wrote {count} cards -> {catalog_path} ({catalog_size / (1024 * 1024):.1f} MB)", flush=True)
    print(f"Meta -> {meta_path}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
