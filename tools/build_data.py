"""Build Data/TalentData.lua from the DB2 tables in tools/db2/ (fetch_db2.py).

For every class tree it derives, per talent:
  - mods:    spells the talent changes (spell-modifier auras matched by class
             mask, action-bar overrides, procs, plus abilities its description
             names for server-scripted "dummy" auras) with a short effect text
  - stats:   what it scales with / improves
  - note:    proc chains and resource loops in plain words
  - ranks:   per-rank description text with the tooltip tokens resolved
  - classic: how it differs from the Classic Era talent of the same name
and per spell: name and what the spell scales with, plus a map from every
rank / proc spell ID to its base spell (for damage meter attribution).

Hand-written corrections live in tools/overrides/<CLASS>.json and are merged
last. The output is deterministic (sorted keys) so diffs stay readable.

Usage: python tools/build_data.py                 # write Data/TalentData.lua
       python tools/build_data.py --summary MAGE  # readable overview of one class
"""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB2 = ROOT / "db2"
ERA = DB2 / "era"
OVERRIDES = ROOT / "overrides"
OUT = ROOT.parent / "Data" / "TalentData.lua"

# classID -> (token, trait tree ID, spell family). Tree IDs confirmed in game
# by /batlas probe (docs/probe-results.md).
CLASSES = {
    1: ("WARRIOR", 1117, 4), 2: ("PALADIN", 1100, 10), 3: ("HUNTER", 1091, 9),
    4: ("ROGUE", 1111, 8), 5: ("PRIEST", 1114, 6), 7: ("SHAMAN", 1082, 11),
    8: ("MAGE", 1112, 3), 9: ("WARLOCK", 1116, 5), 11: ("DRUID", 1089, 7),
}

# Spell effects and auras (modern enum values).
E_APPLY_AURA, E_SCHOOL_DAMAGE, E_ENERGIZE, E_WEAPON_DAMAGE_NOSCHOOL = 6, 2, 30, 17
E_TRIGGER_SPELL, E_WEAPON_DAMAGE, E_WEAPON_PCT, E_NORMALIZED_WEAPON = 64, 31, 58, 121
E_HEAL, E_LEARN_SPELL = 10, 36
A_DUMMY, A_PERIODIC_DAMAGE, A_PERIODIC_HEAL, A_PERIODIC_ENERGIZE = 4, 3, 8, 24
A_PROC_TRIGGER, A_PROC_TRIGGER_DAMAGE = 42, 43
A_ADD_FLAT, A_ADD_PCT = 107, 108
A_OVERRIDE_ACTIONBAR = 332
A_MOD_POWER_REGEN, A_MOD_POWER_REGEN_PCT = 85, 110
A_MOD_DAMAGE_DONE_PCT = 79

POWER = {0: "Mana", 1: "Rage", 2: "Focus", 3: "Energy"}
POWER_SCALE = {1: 10}  # rage is stored x10
SCHOOLS = [(1, "Physical"), (2, "Holy"), (4, "Fire"), (8, "Nature"), (16, "Frost"), (32, "Shadow"), (64, "Arcane")]

# Aura -> stat chip for talents that change a stat directly.
STAT_AURAS = {
    13: "Spell power", 15: "Damage shield", 22: "Resistance", 29: "Stats", 47: "Parry", 49: "Dodge",
    51: "Block", 52: "Crit", 54: "Hit", 55: "Spell hit", 57: "Spell crit", 65: "Spell haste",
    71: "Spell crit", 79: "Damage", 85: "Regen", 99: "Attack power", 101: "Armor", 102: "Attack power",
    110: "Regen", 123: "Penetration", 133: "Health", 135: "Healing", 137: "Stats", 138: "Haste",
    142: "Armor", 150: "Block value", 158: "Block value", 166: "Attack power", 189: "Ratings",
    192: "Haste", 200: "Experience", 290: "Crit", 319: "Haste", 134: "Spirit", 30: "Defense",
}
STAT_NAMES = {0: "Strength", 1: "Agility", 2: "Stamina", 3: "Intellect", 4: "Spirit"}

# SpellModOp (EffectMiscValue_0 of auras 107/108): (label, unit kind).
MOD_OPS = {
    0: ("damage", "pct"), 1: ("duration", "ms"), 2: ("threat", "pct"), 3: ("effect 1", "pct"),
    4: ("charges", "n"), 5: ("range", "yd"), 6: ("radius", "yd"), 7: ("crit chance", "pct"),
    8: ("all effects", "pct"), 9: ("pushback", "pct"), 10: ("cast time", "ms"), 11: ("cooldown", "ms"),
    12: ("effect 2", "pct"), 13: ("resist", "n"), 14: ("cost", "cost"), 15: ("crit damage", "pct"),
    16: ("hit chance", "pct"), 17: ("targets", "n"), 18: ("proc chance", "pct"), 19: ("tick period", "ms"),
    20: ("chain damage", "pct"), 21: ("global cooldown", "ms"), 22: ("periodic damage", "pct"),
    23: ("effect 3", "pct"), 24: ("bonus coefficient", "pct"), 25: ("triggered damage", "pct"),
    26: ("proc rate", "pct"), 27: ("amplitude", "pct"), 28: ("dispel resist", "pct"),
    31: ("stacks", "n"), 34: ("cost", "cost"), 37: ("max stacks", "n"), 38: ("proc cooldown", "ms"),
    39: ("cost", "cost"),
}
CRIT_OPS = {7, 15}

# Auras that change every melee swing: linked to Auto Attack so they show up
# as synergies and in fight attribution.
AUTO_ATTACK = 6603
MELEE_AURAS = {52: "more melee crits", 54: "more melee hits", 138: "faster swings", 79: "more damage"}

JUNK = re.compile(r"(?i)(dummy|test|dnd|dnt|unused|deprecated|placeholder)|\[")

# Words too generic to link a description to an ability.
GENERIC_NAMES = {"Attack", "Shoot", "Throw", "Auto Shot", "Charge", "Block", "Parry", "Dodge"}


def read(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def num(s: str | None) -> float:
    try:
        return float(s) if s not in (None, "") else 0.0
    except ValueError:
        return 0.0


def u32(s: str | None) -> int:
    return int(num(s)) & 0xFFFFFFFF


def fmt(x: float, decimals: int | None = None) -> str:
    if decimals is not None:
        return f"{x:.{decimals}f}"
    if abs(x - round(x)) < 1e-6:
        return str(int(round(x)))
    return f"{x:.2f}".rstrip("0").rstrip(".")


def duration_text(ms: float) -> str:
    if ms <= 0:
        return "until cancelled"
    sec = ms / 1000
    if sec >= 60 and sec % 60 == 0:
        mins = int(sec // 60)
        return f"{mins} min"
    return f"{fmt(sec)} sec"


class Db:
    """The DB2 tables, indexed."""

    def __init__(self, d: Path):
        self.names = {int(r["ID"]): r["Name_lang"] for r in read(d / "SpellName.csv")}
        self.ids_by_name: dict[str, list[int]] = defaultdict(list)
        for sid, n in self.names.items():
            self.ids_by_name[n].append(sid)
        self.desc = {int(r["ID"]): r["Description_lang"] for r in read(d / "Spell.csv")}
        self.effects: dict[int, list[dict]] = defaultdict(list)
        for r in read(d / "SpellEffect.csv"):
            if r.get("DifficultyID", "0") in ("0", ""):
                self.effects[int(r["SpellID"])].append(r)
        for lst in self.effects.values():
            lst.sort(key=lambda r: int(r["EffectIndex"]))
        self.options = {int(r["SpellID"]): r for r in read(d / "SpellClassOptions.csv")}
        self.misc = {}
        for r in read(d / "SpellMisc.csv"):
            if r.get("DifficultyID", "0") in ("0", ""):
                self.misc[int(r["SpellID"])] = r
        self.durations = {int(r["ID"]): num(r["Duration"]) for r in read(d / "SpellDuration.csv")}
        radius_file = d / "SpellRadius.csv"
        self.radii = {int(r["ID"]): num(r["Radius"]) for r in read(radius_file)} if radius_file.exists() else {}
        self.aura_options = {}
        for r in read(d / "SpellAuraOptions.csv"):
            if r.get("DifficultyID", "0") in ("0", ""):
                self.aura_options[int(r["SpellID"])] = r
        self.power = defaultdict(list)
        for r in read(d / "SpellPower.csv"):
            self.power[int(r["SpellID"])].append(r)
        self.class_spells: dict[int, set[int]] = defaultdict(set)  # classID -> spells
        for r in read(d / "SkillLineAbility.csv"):
            mask = u32(r["ClassMask"])
            for cid in CLASSES:
                if mask & (1 << (cid - 1)):
                    self.class_spells[cid].add(int(r["Spell"]))
        self.nodes = {int(r["ID"]): r for r in read(d / "TraitNode.csv")}
        self.node_entries: dict[int, list[int]] = defaultdict(list)
        for r in sorted(read(d / "TraitNodeXTraitNodeEntry.csv"), key=lambda r: int(r["_Index"])):
            self.node_entries[int(r["TraitNodeID"])].append(int(r["TraitNodeEntryID"]))
        self.entries = {int(r["ID"]): r for r in read(d / "TraitNodeEntry.csv")}
        self.definitions = {int(r["ID"]): r for r in read(d / "TraitDefinition.csv")}
        self.def_of_spell = {int(num(r["SpellID"])): int(r["ID"]) for r in self.definitions.values() if num(r["SpellID"])}
        # Per-rank effect values of talents: (definitionID, effectIndex) -> {rank: value}.
        points: dict[int, list[tuple[float, float]]] = defaultdict(list)
        for r in read(d / "CurvePoint.csv"):
            points[int(r["CurveID"])].append((num(r["Pos_0"]), num(r["Pos_1"])))
        self.rank_curves: dict[tuple[int, int], dict[int, float]] = {}
        for r in read(d / "TraitDefinitionEffectPoints.csv"):
            curve = sorted(points.get(int(r["CurveID"]), []))
            if curve:
                self.rank_curves[(int(r["TraitDefinitionID"]), int(r["EffectIndex"]))] = {int(round(x)): y for x, y in curve}

    def effect_value(self, sid: int, eff: dict, rank: int) -> float:
        """An effect's value at a talent rank: the rank curve when the talent has one."""
        curve = self.rank_curves.get((self.def_of_spell.get(sid, 0), int(eff["EffectIndex"])))
        if curve:
            lower = [k for k in curve if k <= rank]
            return curve[max(lower)] if lower else 0.0
        return num(eff["EffectBasePointsF"])

    def name(self, sid: int) -> str:
        return self.names.get(sid, "")

    def family(self, sid: int) -> int:
        o = self.options.get(sid)
        return int(num(o["SpellClassSet"])) if o else 0

    def mask(self, sid: int) -> tuple[int, int, int, int]:
        o = self.options.get(sid)
        if not o:
            return (0, 0, 0, 0)
        return tuple(u32(o[f"SpellClassMask_{i}"]) for i in range(4))  # type: ignore[return-value]

    def duration(self, sid: int) -> float:
        m = self.misc.get(sid)
        return self.durations.get(int(num(m["DurationIndex"])), 0.0) if m else 0.0

    def is_passive(self, sid: int) -> bool:
        m = self.misc.get(sid)
        return bool(m) and bool(u32(m["Attributes_0"]) & 0x40)

    def school(self, sid: int) -> str:
        m = self.misc.get(sid)
        mask = int(num(m["SchoolMask"])) if m else 0
        return "/".join(n for bit, n in SCHOOLS if mask & bit) or "Physical"

    def power_type(self, sid: int) -> int | None:
        rows = self.power.get(sid)
        return int(num(rows[0]["PowerType"])) if rows else None


# Tooltip tokens -----------------------------------------------------------------

TOKEN = re.compile(r"\$(?:(\d+)?([a-zA-Z])(\d)?)")


class Describer:
    """Resolves $tokens in a spell description for a given rank."""

    def __init__(self, db: Db):
        self.db = db

    def value(self, sid: int, letter: str, index: int, rank: int, own: int) -> float | None:
        db = self.db
        effects = db.effects.get(sid, [])
        eff = next((e for e in effects if int(e["EffectIndex"]) == index - 1), None)
        lo = letter.lower()

        def base(e: dict) -> float:
            return db.effect_value(sid, e, rank) if sid == own else num(e["EffectBasePointsF"])
        if lo in ("s", "m", "w"):
            if not eff:
                return None
            v = base(eff)
            return abs(v) if lo == "s" else v
        if lo == "o":
            if not eff:
                return None
            period = num(eff["EffectAuraPeriod"]) or 3000
            return abs(base(eff)) * (db.duration(sid) / period)
        if lo == "t":
            return num(eff["EffectAuraPeriod"]) / 1000 if eff else None
        if lo == "a":
            if not eff:
                return None
            return db.radii.get(int(num(eff["EffectRadiusIndex_0"]))) or db.radii.get(int(num(eff["EffectRadiusIndex_1"])))
        if lo == "h":
            ao = db.aura_options.get(sid)
            return num(ao["ProcChance"]) if ao else None
        if lo == "n":
            ao = db.aura_options.get(sid)
            return num(ao["ProcCharges"]) if ao else None
        if lo == "u":
            ao = db.aura_options.get(sid)
            return num(ao["CumulativeAura"]) if ao else None
        if lo == "x":
            return num(eff["EffectChainTargets"]) if eff else None
        if lo == "e":
            return num(eff["EffectAmplitude"]) if eff else None
        if lo == "b":
            return num(eff["EffectPointsPerResource"]) if eff else None
        return None

    def token_text(self, m: re.Match, sid: int, rank: int) -> str:
        ref, letter, idx = m.group(1), m.group(2), m.group(3)
        target = int(ref) if ref else sid
        if letter.lower() == "d":
            return duration_text(self.db.duration(target))
        v = self.value(target, letter, int(idx or 1), rank, sid)
        return fmt(v) if v is not None else m.group(0)

    def numeric(self, expr: str, sid: int, rank: int) -> float | None:
        def sub(m: re.Match) -> str:
            ref, letter, idx = m.group(1), m.group(2), m.group(3)
            target = int(ref) if ref else sid
            if letter.lower() == "d":
                return repr(self.db.duration(target) / 1000)
            v = self.value(target, letter, int(idx or 1), rank, sid)
            return repr(v if v is not None else 0.0)
        body = TOKEN.sub(sub, expr)
        if not re.fullmatch(r"[\d\s.+\-*/()]*", body) or not body.strip():
            return None
        try:
            return float(eval(body, {"__builtins__": {}}, {}))  # noqa: S307 - digits and operators only
        except Exception:
            return None

    def describe(self, sid: int, rank: int) -> str:
        text = self.db.desc.get(sid, "") or ""
        if not text:
            return ""
        # $?s123[yes][no] and $?a123[yes][no]: assume the condition is false.
        for _ in range(5):
            text = re.sub(r"\$\?[!a-z]*\d+\[([^\[\]]*)\]\[([^\[\]]*)\]", r"\2", text)
        text = re.sub(r"\$@spell(?:desc|name)(\d+)", lambda m: self.db.name(int(m.group(1))), text)
        # ${expr}.N
        def expr(m: re.Match) -> str:
            v = self.numeric(m.group(1), sid, rank)
            decimals = int(m.group(2)) if m.group(2) else None
            return fmt(abs(v), decimals) if v is not None else "?"
        text = re.sub(r"\$\{([^{}]*)\}(?:\.(\d))?", expr, text)
        # $/10;s1 and $*2;s1
        def scaled(m: re.Match) -> str:
            op, n, ref, letter, idx = m.group(1), float(m.group(2)), m.group(3), m.group(4), m.group(5)
            target = int(ref) if ref else sid
            v = self.value(target, letter, int(idx or 1), rank, sid)
            if v is None:
                return "?"
            return fmt(abs(v / n if op == "/" else v * n))
        text = re.sub(r"\$([/*])(\d+(?:\.\d+)?);(\d+)?([a-zA-Z])(\d)?", scaled, text)
        # $lsingular:plural;
        text = re.sub(r"\$[lL]([^:;]*):([^;]*);", r"\2", text)
        text = TOKEN.sub(lambda m: self.token_text(m, sid, rank), text)
        text = re.sub(r"\$\w+", "?", text)  # anything left unresolved
        text = re.sub(r"[ \t]+\n", "\n", text)
        text = re.sub(r"\n[ \t]+", "\n", text)
        return text.strip()


# Talent analysis ------------------------------------------------------------------

def rank_values(values: list[float], scale: float = 1.0) -> tuple[str, bool]:
    """('3', False) for one rank, ('1', True) when linear per rank, else ('12/23/35', False)."""
    vals = [abs(v) / scale for v in values]
    if len(vals) == 1:
        return fmt(vals[0]), False
    step = vals[0]
    if all(abs(v - step * (i + 1)) < 1e-6 for i, v in enumerate(vals)):
        return fmt(step), True
    return "/".join(fmt(v) for v in vals), False


def mod_fx(db: Db, sid: int, eff: dict, target: int, max_ranks: int) -> str:
    op = int(num(eff["EffectMiscValue_0"]))
    aura = int(num(eff["EffectAura"]))
    label, unit = MOD_OPS.get(op, (f"property {op}", "n"))
    values = [db.effect_value(sid, eff, r) for r in range(1, max_ranks + 1)]
    sign = "+" if values[-1] >= 0 else "−"
    scale, suffix = 1.0, f" {label}"
    if unit == "cost":
        if aura == A_ADD_PCT:
            suffix = "% cost"
        else:
            pt = db.power_type(target)
            key = pt if pt is not None else -1
            scale = POWER_SCALE.get(key, 1)
            suffix = f" {POWER.get(key, 'resource')} cost"
    elif unit == "ms" and aura == A_ADD_FLAT:
        scale, suffix = 1000.0, f" sec {label}"
    elif aura == A_ADD_PCT or unit == "pct":
        suffix = f"% {label}"
    elif unit == "yd":
        suffix = f" yd {label}"
    text, per_rank = rank_values(values, scale)
    return f"{sign}{text}{suffix}" + (" per rank" if per_rank else "")


def spell_scaling(db: Db, sid: int) -> list[str]:
    """What a spell's own damage/healing scales with."""
    out = []
    for e in db.effects.get(sid, []):
        effect, aura = int(num(e["Effect"])), int(num(e["EffectAura"]))
        if effect in (E_WEAPON_DAMAGE, E_WEAPON_PCT, E_NORMALIZED_WEAPON, E_WEAPON_DAMAGE_NOSCHOOL):
            out.append("Weapon damage")
        if num(e["BonusCoefficientFromAP"]) > 0:
            out.append("Attack power")
        damaging = effect in (E_SCHOOL_DAMAGE, E_HEAL) or aura in (A_PERIODIC_DAMAGE, A_PERIODIC_HEAL)
        # Physical abilities carry a default coefficient of 1 that means nothing.
        if num(e["EffectBonusCoefficient"]) > 0 and damaging and db.school(sid) != "Physical":
            out.append("Healing power" if effect == E_HEAL or aura == A_PERIODIC_HEAL else "Spell power")
    seen: list[str] = []
    for s in out:
        if s not in seen:
            seen.append(s)
    return seen


class ClassBuilder:
    def __init__(self, db: Db, describer: Describer, cid: int, era: dict | None):
        self.db, self.describer, self.cid = db, describer, cid
        self.token, self.tree, self.fam = CLASSES[cid]
        self.era = era
        # Candidate spells: this class's family.
        self.family_spells = [s for s in db.options if db.family(s) == self.fam and db.name(s)]
        self.ability_ids = db.class_spells[cid]
        self.by_name: dict[str, list[int]] = defaultdict(list)
        # Developer leftovers in the class data ("Jeff Dummy 1", "[DNT]") are not abilities.
        self.family_spells = [s for s in self.family_spells if not JUNK.search(db.name(s))]
        for s in self.family_spells:
            self.by_name[db.name(s)].append(s)
        for s in self.ability_ids:
            if db.name(s) and s not in self.family_spells and not JUNK.search(db.name(s)):
                self.by_name[db.name(s)].append(s)
        self.key_of_name = {n: min(ids) for n, ids in self.by_name.items()}
        # Melee swings are reported as 6603 whatever the class ability is called.
        for n, ids in self.by_name.items():
            if AUTO_ATTACK in ids or n == db.name(AUTO_ATTACK):
                self.key_of_name[n] = AUTO_ATTACK
        self.key_of_name[db.name(AUTO_ATTACK)] = AUTO_ATTACK
        self.spells: dict[int, dict] = {}
        self.rank_map: dict[int, int] = {}
        self.procs: dict[int, list[int]] = {}
        self.school_cache: dict[str, list[int]] = {}
        # Every spell by name, for proc damage siblings (the meter reports the
        # damage spell, which often has no class options of its own).
        self.db_by_name = db.ids_by_name

    def key(self, sid: int) -> int:
        return self.key_of_name.get(self.db.name(sid), sid)

    def use_spell(self, sid: int) -> int:
        k = self.key(sid)
        if k not in self.spells:
            name = self.db.name(sid)
            scaling = []
            for s in self.by_name.get(name, [sid]):
                for x in spell_scaling(self.db, s):
                    if x not in scaling:
                        scaling.append(x)
            self.spells[k] = {"name": name, "school": self.db.school(sid), "scales": scaling}
            for s in self.by_name.get(name, [sid]):
                if s != k:
                    self.rank_map[s] = k
        return k

    def masked_targets(self, eff: dict) -> list[int]:
        mask = tuple(u32(eff[f"EffectSpellClassMask_{i}"]) for i in range(4))
        if not any(mask):
            return []
        hits = []
        for s in self.family_spells:
            sm = self.db.mask(s)
            if any(a & b for a, b in zip(mask, sm)):
                hits.append(s)
        return hits

    def is_ability(self, sid: int) -> bool:
        name = self.db.name(sid)
        return any(s in self.ability_ids for s in self.by_name.get(name, []))

    def school_abilities(self, school: str) -> list[int]:
        """Class abilities of a school that deal damage or heal (one per name)."""
        if school in self.school_cache:
            return self.school_cache[school]
        out = []
        for name, ids in sorted(self.by_name.items()):
            k = self.key_of_name[name]
            if k == AUTO_ATTACK or not any(s in self.ability_ids for s in ids):
                continue
            if self.db.school(k) != school or self.db.is_passive(k):
                continue
            if any(int(num(e["Effect"])) in (E_SCHOOL_DAMAGE, E_HEAL, E_WEAPON_DAMAGE, E_WEAPON_PCT, E_NORMALIZED_WEAPON)
                   or int(num(e["EffectAura"])) in (A_PERIODIC_DAMAGE, A_PERIODIC_HEAL)
                   for s in ids for e in self.db.effects.get(s, [])):
                out.append(k)
        self.school_cache[school] = out
        return out

    def proc_chain(self, sid: int, depth: int = 0, seen: set | None = None) -> list[int]:
        seen = seen or set()
        out = []
        for e in self.db.effects.get(sid, []):
            trig = int(num(e["EffectTriggerSpell"]))
            aura, effect = int(num(e["EffectAura"])), int(num(e["Effect"]))
            if trig and trig not in seen and (aura in (A_PROC_TRIGGER, A_PROC_TRIGGER_DAMAGE) or effect == E_TRIGGER_SPELL or depth > 0):
                seen.add(trig)
                out.append(trig)
                if depth < 3:
                    out.extend(self.proc_chain(trig, depth + 1, seen))
        return out

    def energizes(self, sid: int) -> str | None:
        for e in self.db.effects.get(sid, []):
            effect, aura = int(num(e["Effect"])), int(num(e["EffectAura"]))
            if effect == E_ENERGIZE or aura in (A_PERIODIC_ENERGIZE, A_MOD_POWER_REGEN, A_MOD_POWER_REGEN_PCT):
                return POWER.get(int(num(e["EffectMiscValue_0"])), "resource")
        return None

    def talent(self, node_id: int, entry_id: int) -> tuple[int, dict] | None:
        db = self.db
        entry = db.entries[entry_id]
        definition = db.definitions.get(int(entry["TraitDefinitionID"]))
        if not definition:
            return None
        sid = int(num(definition["SpellID"]))
        if not sid:
            return None
        max_ranks = int(num(entry["MaxRanks"])) or 1
        name = definition["OverrideName_lang"] or db.name(sid)
        mods: dict[int, str] = {}
        stats: list[str] = []
        notes: list[str] = []
        dummy = False

        def add_mod(target: int, fx: str) -> None:
            if not db.name(target):
                return
            k = self.use_spell(target)
            if k not in mods:
                mods[k] = fx

        def add_stat(s: str) -> None:
            if s and s not in stats:
                stats.append(s)

        if not db.is_passive(sid):
            add_mod(sid, "grants the ability")
            for s in spell_scaling(db, sid):
                add_stat(s)

        for e in db.effects.get(sid, []):
            effect, aura = int(num(e["Effect"])), int(num(e["EffectAura"]))
            if effect != E_APPLY_AURA:
                continue
            if aura in (A_ADD_FLAT, A_ADD_PCT):
                op = int(num(e["EffectMiscValue_0"]))
                for t in self.masked_targets(e):
                    if self.is_ability(t) or t in self.spells or self.key(t) in self.spells:
                        add_mod(t, mod_fx(db, sid, e, t, max_ranks))
                if op in CRIT_OPS:
                    add_stat("Crit")
            elif aura == A_OVERRIDE_ACTIONBAR:
                base = int(num(e["EffectMiscValue_0"]))
                if base:
                    add_mod(base, "replaced by an improved version")
            elif aura == A_DUMMY:
                dummy = True
            if aura in MELEE_AURAS and (aura != A_MOD_DAMAGE_DONE_PCT or int(num(e["EffectMiscValue_0"])) & 1):
                add_mod(AUTO_ATTACK, MELEE_AURAS[aura])
            elif aura in STAT_AURAS:
                label = STAT_AURAS[aura]
                if aura in (29, 137):
                    # The stat index is not reliable here; the text names it.
                    named = re.search(r"(Strength|Agility|Stamina|Intellect|Spirit)", db.desc.get(sid, "") or "")
                    label = named.group(1) if named else "All stats"
                add_stat(label)

        chain = self.proc_chain(sid)
        # Spells the description points at by ID (e.g. "$412609d") belong to
        # the talent too: often the real effect of a scripted proc.
        text = db.desc.get(sid, "") or ""
        for ref in re.findall(r"\$\{?\$?(\d{3,})[a-zA-Z]", text):
            r = int(ref)
            if r != sid and db.name(r) and r not in chain:
                chain.append(r)
        if chain:
            names = []
            for t in chain:
                n = db.name(t)
                if n and n != name and n not in names:
                    names.append(n)
                    if self.is_ability(t):
                        add_mod(t, "triggered by this talent")
            if names:
                notes.append("Proc chain: " + " → ".join([name] + names) + ".")
        self.procs[sid] = chain
        power = self.energizes(sid) or next((p for p in (self.energizes(t) for t in chain) if p), None)
        if power:
            notes.append(f"Resource loop: generates {power} for your spenders.")
        if any("cost" in fx for fx in mods.values()):
            notes.append("Resource: makes the modified abilities cheaper.")

        # Scripted (dummy) talents and anything else: abilities named in the
        # text. Longest names first, each match blanked out so "Shield" does
        # not match again inside "Shield Wall".
        rest = text
        for ability_name in sorted(self.by_name, key=len, reverse=True):
            if len(ability_name) < 5 or ability_name in GENERIC_NAMES:
                continue
            if not any(s in self.ability_ids for s in self.by_name[ability_name]):
                continue
            pattern = r"\b" + re.escape(ability_name) + r"\b"
            if re.search(pattern, rest):
                rest = re.sub(pattern, "#", rest)
                if ability_name == name:
                    continue
                k = self.key_of_name[ability_name]
                if self.use_spell(k) not in mods:
                    mods[self.use_spell(k)] = "named in its effect"
        # "your Fire spells", "Holy damage", "Shadow and Frost spells": link
        # every damaging or healing ability of that school.
        for _, school in SCHOOLS:
            if re.search(r"\b" + school + r"\b(?:[^.]{0,30}?)\b(spells?|damage|heals?|effects|attacks|critical)\b", rest):
                for ability in self.school_abilities(school):
                    k = self.use_spell(ability)
                    if k not in mods:
                        mods[k] = f"all {school} spells" if school != "Physical" else "all Physical attacks"
        if dummy and not notes:
            notes.append("Part of this effect is scripted by the server; the description is the reference.")

        for k, fx in list(mods.items()):
            for s in self.spells.get(k, {}).get("scales", []):
                if len(stats) < 4:
                    add_stat(s)

        data = {
            "name": name, "node": node_id, "max": max_ranks,
            "mods": [{"spell": k, "fx": fx} for k, fx in sorted(mods.items())],
            "stats": stats[:4],
            "ranks": [self.describer.describe(sid, r) for r in range(1, max_ranks + 1)],
        }
        if notes:
            data["note"] = " ".join(notes)
        classic = self.classic_diff(name, max_ranks, sid)
        if classic:
            data["classic"] = classic
        return sid, data

    def classic_diff(self, name: str, max_ranks: int, sid: int) -> str | None:
        if not self.era:
            return None
        era_talent = self.era["talents"].get((self.cid, name))
        if not era_talent:
            return "New in Forever."
        ranks = era_talent
        parts = []
        if len(ranks) != max_ranks:
            parts.append(f"{len(ranks)} ranks in Classic, {max_ranks} here.")
        era_v = self.era["value"](ranks[0])
        values = [self.db.effect_value(sid, e, 1) for e in self.db.effects.get(sid, [])
                  if num(e["EffectAura"]) not in (A_PROC_TRIGGER, A_PROC_TRIGGER_DAMAGE)]
        now_v = max(values, key=abs) if values else None
        if era_v and now_v and abs(era_v) != abs(now_v):
            parts.append(f"Rank 1 value {fmt(abs(era_v))} in Classic, {fmt(abs(now_v))} here.")
        return " ".join(parts) if parts else "Same as Classic."

    def build(self) -> dict:
        talents = {}
        for node_id, node in sorted(self.db.nodes.items()):
            if int(node["TraitTreeID"]) != self.tree:
                continue
            for entry_id in self.db.node_entries.get(node_id, []):
                res = self.talent(node_id, entry_id)
                if res:
                    talents[res[0]] = res[1]
        # Damage from spells a talent triggers (Deep Wound, extra attacks...)
        # is that talent's own: procOf[spellID] = talent spellID. Same-name
        # siblings count too (the meter reports the damage spell, not the aura).
        proc_of: dict[int, int] = {}
        for sid, chain in sorted(self.procs.items()):
            for t_sid in chain:
                if self.is_ability(t_sid):
                    continue
                for s in [t_sid] + sorted(self.db_by_name.get(self.db.name(t_sid), [])):
                    proc_of.setdefault(s, sid)
        if AUTO_ATTACK in self.spells:
            self.spells[AUTO_ATTACK]["name"] = "Auto Attack"
        return {"talents": talents, "spells": self.spells, "rankOf": self.rank_map, "procOf": proc_of}


def load_era() -> dict | None:
    if not (ERA / "Talent.csv").exists():
        return None
    names = {int(r["ID"]): r["Name_lang"] for r in read(ERA / "SpellName.csv")}
    eff: dict[int, list[dict]] = defaultdict(list)
    for r in read(ERA / "SpellEffect.csv"):
        eff[int(r["SpellID"])].append(r)
    talents = {}
    for r in read(ERA / "Talent.csv"):
        ranks = [int(num(r[f"SpellRank_{i}"])) for i in range(9) if int(num(r[f"SpellRank_{i}"]))]
        if ranks:
            talents[(int(r["ClassID"]), names.get(ranks[0], ""))] = ranks

    def value(sid: int) -> float | None:
        """The rank's strongest effect value (Classic stores base points - 1)."""
        best = None
        for e in eff.get(sid, []):
            if num(e["EffectAura"]) in (A_PROC_TRIGGER, A_PROC_TRIGGER_DAMAGE):
                continue  # the value lives in the triggered spell
            bp, dice = num(e["EffectBasePoints"]), num(e.get("EffectDieSides"))
            v = bp + (1 if dice >= 1 else 0)
            if best is None or abs(v) > abs(best):
                best = v
        return best
    return {"talents": talents, "value": value}


def merge_overrides(builder: "ClassBuilder", data: dict) -> None:
    path = OVERRIDES / f"{builder.token}.json"
    if not path.exists():
        return
    over = json.loads(path.read_text(encoding="utf-8"))
    by_name = {t["name"]: sid for sid, t in data["talents"].items()}
    for key, patch in over.get("talents", {}).items():
        sid = int(key) if key.isdigit() else by_name.get(key)
        if sid is None or sid not in data["talents"]:
            raise SystemExit(f"{path.name}: unknown talent {key!r}")
        t = data["talents"][sid]
        if patch.get("replaceMods"):
            t["mods"] = []
        for m in patch.get("mods", []):
            spell = m["spell"]
            if isinstance(spell, str):
                if spell not in builder.key_of_name:
                    raise SystemExit(f"{path.name}: {key}: unknown spell {m['spell']!r}")
                spell = builder.use_spell(builder.key_of_name[spell])
            else:
                spell = builder.use_spell(int(spell))
            t["mods"] = [x for x in t["mods"] if x["spell"] != spell] + [{"spell": spell, "fx": m["fx"]}]
            t["mods"].sort(key=lambda x: x["spell"])
        for drop in patch.get("dropMods", []):
            t["mods"] = [x for x in t["mods"] if data["spells"].get(x["spell"], {}).get("name") != drop]
        for field in ("note", "stats", "classic"):
            if field in patch:
                t[field] = patch[field]


# Lua output ----------------------------------------------------------------------

def lua(v, indent: int = 0) -> str:
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return fmt(v)
    if isinstance(v, str):
        s = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
        return f'"{s}"'
    if isinstance(v, list):
        if not v:
            return "{}"
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        return "{\n" + "".join(f"{pad}\t{lua(x, indent + 1)},\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        keys = sorted(v, key=lambda k: (isinstance(k, str), k))
        if all(isinstance(k, str) for k in keys) and all(not isinstance(v[k], (dict, list)) for k in keys) and len(keys) <= 3:
            return "{ " + ", ".join(f"{k} = {lua(v[k])}" for k in keys) + " }"
        out = "{\n"
        for k in keys:
            key = f"[{k}]" if isinstance(k, int) else k
            out += f"{pad}\t{key} = {lua(v[k], indent + 1)},\n"
        return out + pad + "}"
    raise TypeError(type(v))


def summary(token: str) -> int:
    """Readable per-talent overview of one class, for writing overrides."""
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    cid = next(c for c, v in CLASSES.items() if v[0] == token.upper())
    db = Db(DB2)
    builder = ClassBuilder(db, Describer(db), cid, load_era())
    data = builder.build()
    merge_overrides(builder, data)
    weak_only = "--weak" in sys.argv
    for sid, t in sorted(data["talents"].items(), key=lambda kv: kv[1]["name"]):
        weak = not t["mods"] or "scripted" in t.get("note", "") or all(m["fx"] == "named in its effect" for m in t["mods"])
        if weak_only and not weak:
            continue
        mods = "; ".join(f"{data['spells'][m['spell']]['name']}: {m['fx']}" for m in t["mods"])
        print(f"{t['name']} [{sid}] {mods} | {', '.join(t['stats'])} | {t.get('note', '')}")
        print(f"    {t['ranks'][-1][:220]}")
    return 0


def main() -> int:
    import sys
    if len(sys.argv) > 2 and sys.argv[1] == "--summary":
        return summary(sys.argv[2])
    build = (DB2 / "build.txt").read_text(encoding="utf-8").strip()
    era_build = (ERA / "build.txt").read_text(encoding="utf-8").strip() if (ERA / "build.txt").exists() else None
    db = Db(DB2)
    describer = Describer(db)
    era = load_era()
    lines = [
        "-- Generated by tools/build_data.py. Do not edit; change the script or tools/overrides/ instead.",
        f"-- Source: WoW Forever {build} DB2 tables (wago.tools)" + (f", Classic Era {era_build} for the comparison." if era_build else "."),
        "local addonName, ns = ...",
        "",
        f'ns.DATA_BUILD = "{build}"',
        "ns.ClassData = {}",
        "",
    ]
    total = 0
    for cid in sorted(CLASSES):
        builder = ClassBuilder(db, describer, cid, era)
        data = builder.build()
        merge_overrides(builder, data)
        data["build"] = build
        total += len(data["talents"])
        linked = sum(1 for t in data["talents"].values() if t["mods"])
        print(f"{CLASSES[cid][0]:8} talents {len(data['talents']):3}  with spell links {linked:3}  spells {len(data['spells']):3}  rank ids {len(data['rankOf']):4}")
        lines.append(f"-- {CLASSES[cid][0]}")
        lines.append(f"ns.ClassData[{cid}] = " + lua(data))
        lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{total} talents -> {OUT.relative_to(ROOT.parent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
