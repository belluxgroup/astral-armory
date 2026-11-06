"""Upload the VFX textures to Roblox through the Open Cloud Assets API.

Usage: python tools/upload_textures.py <creatorUserId>

Reads the API key from %USERPROFILE%\\.roblox_api_key (never from the repo, never printed).
Writes the resulting ids to assets/textures/asset_ids.json, keyed by AssetIds slot.
Already-uploaded slots in that file are skipped, so a failed run can simply be re-run.
"""

import json
import os
import sys
import time
from pathlib import Path

import requests

API = "https://apis.roblox.com/assets/v1"
ROOT = Path(__file__).resolve().parent.parent
TEXTURES = ROOT / "assets" / "textures"
OUT = TEXTURES / "asset_ids.json"

# AssetIds slot -> file. The hero ring replaces the procedural ring_runes.png.
SLOTS = {
    "glow_soft": "glow_soft.png",
    "glow_star": "glow_star.png",
    "spark": "spark.png",
    "smoke_soft": "smoke_soft.png",
    "ring_runes": "hero_ring_runes.png",
    "hex_cell": "hex_cell.png",
    "slash_arc": "slash_arc.png",
    "beam_core": "beam_core.png",
    "explosion_flipbook_4x4": "explosion_flipbook_4x4.png",
    "aura_flame": "hero_aura_flame.png",
}


def load_key() -> str:
    path = Path(os.environ.get("USERPROFILE", str(Path.home()))) / ".roblox_api_key"
    key = path.read_text(encoding="utf-8-sig").strip()
    if not key:
        sys.exit(f"empty key file: {path}")
    return key


def upload(session: requests.Session, user_id: str, slot: str, file: Path) -> str:
    request = {
        "assetType": "Image",
        "displayName": f"AstralArmory_{slot}",
        "description": "Astral Armory VFX texture",
        "creationContext": {"creator": {"userId": user_id}},
    }
    with file.open("rb") as fh:
        resp = session.post(
            f"{API}/assets",
            files={
                "request": (None, json.dumps(request), "application/json"),
                "fileContent": (file.name, fh, "image/png"),
            },
            timeout=60,
        )
    if resp.status_code >= 400:
        raise RuntimeError(f"upload {slot}: HTTP {resp.status_code} {resp.text[:300]}")
    op = resp.json()
    path = op.get("path") or f"operations/{op.get('operationId')}"
    for _ in range(40):
        if op.get("done"):
            break
        time.sleep(2)
        poll = session.get(f"{API}/{path}", timeout=30)
        if poll.status_code >= 400:
            raise RuntimeError(f"poll {slot}: HTTP {poll.status_code} {poll.text[:300]}")
        op = poll.json()
    if not op.get("done"):
        raise RuntimeError(f"upload {slot}: operation did not finish")
    asset_id = (op.get("response") or {}).get("assetId")
    if not asset_id:
        raise RuntimeError(f"upload {slot}: no assetId in {json.dumps(op)[:300]}")
    return str(asset_id)


def main() -> None:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        sys.exit("usage: python tools/upload_textures.py <creatorUserId>")
    user_id = sys.argv[1]
    done = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
    session = requests.Session()
    session.headers["x-api-key"] = load_key()
    failures = 0
    for slot, name in SLOTS.items():
        if slot in done:
            print(f"skip   {slot:24} {done[slot]}")
            continue
        try:
            done[slot] = upload(session, user_id, slot, TEXTURES / name)
            print(f"ok     {slot:24} {done[slot]}")
            OUT.write_text(json.dumps(done, indent=2) + "\n", encoding="utf-8")
        except Exception as err:  # keep going; the rest may still upload
            failures += 1
            print(f"FAIL   {slot:24} {err}")
    print(f"{len(done)}/{len(SLOTS)} uploaded")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
