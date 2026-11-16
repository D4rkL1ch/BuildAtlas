"""Download the DB2 tables build_data.py needs into tools/db2/ (git-ignored).

Forever tables come from wago.tools for the given build (default: latest
"wowf" build). Classic Era tables go to tools/db2/era/ for the
"Changed vs Classic" comparison.

Usage:
    python tools/fetch_db2.py                 # latest WoW Forever build
    python tools/fetch_db2.py 1.60.1.70938    # a specific build
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

PRODUCT = "wowf"
ERA_PRODUCT = "wow_classic_era"
TABLES = [
    # Spells
    "SpellName", "Spell", "SpellEffect", "SpellClassOptions", "SpellMisc", "SpellLevels",
    "SpellCooldowns", "SpellCategories", "SpellPower", "SpellDuration", "SpellAuraOptions",
    "SkillLineAbility", "SkillLine", "ChrClasses",
    # Trait (talent) engine
    "TraitTree", "TraitNode", "TraitNodeEntry", "TraitDefinition", "TraitNodeXTraitNodeEntry",
    "TraitNodeGroup", "TraitNodeGroupXTraitNode", "TraitNodeGroupXTraitCond", "TraitNodeXTraitCond",
    "TraitCond", "TraitEdge", "TraitCurrency", "TraitTreeXTraitCurrency",
    "TraitDefinitionEffectPoints", "Curve", "CurvePoint", "SpellRadius",
    "ChrSpecialization", "SpecSetMember",
]
# Classic Era: talents are the old Talent table; spell effects for the diff.
ERA_TABLES = ["Talent", "TalentTab", "SpellName", "SpellEffect", "SpellMisc", "SpellClassOptions"]
OUT_DIR = Path(__file__).resolve().parent / "db2"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "BuildAtlas build tool"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()


def latest(product: str) -> str:
    builds = json.loads(fetch("https://wago.tools/api/builds"))
    return builds[product][0]["version"]


def fetch_tables(version: str, tables: list[str], out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for table in tables:
        try:
            data = fetch(f"https://wago.tools/db2/{table}/csv?build={version}")
        except Exception as exc:  # a table may not exist in a build
            print(f"{table}: skipped ({exc})")
            continue
        (out / f"{table}.csv").write_bytes(data)
        print(f"{table}: {len(data) // 1024} KB")
    (out / "build.txt").write_text(version + "\n", encoding="utf-8")


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else latest(PRODUCT)
    fetch_tables(version, TABLES, OUT_DIR)
    era = latest(ERA_PRODUCT)
    fetch_tables(era, ERA_TABLES, OUT_DIR / "era")
    print(f"forever {version}, era {era} -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
