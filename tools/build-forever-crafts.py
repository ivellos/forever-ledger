"""Generate factual recipe rows from Wago's permitted, version-pinned CSV exports.

Run from the repository root with Python 3. Downloaded tables stay in the OS temp
directory; --offline uses that cache. No game saved data or addon code is executed.
The client lists recipes, not whether their training/vendor/drop is live on a server.
"""
import argparse
import collections
import csv
import hashlib
import io
import json
import pathlib
import tempfile
import urllib.request

BUILD = "1.60.1.70938"
DATE = "2026-11-14"
TABLES = ("SkillLine", "SkillLineAbility", "SpellName", "SpellEffect", "SpellReagents", "ItemSparse", "ItemDisenchantLoot")
PROFESSIONS = {129: "First Aid", 164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy",
               182: "Herbalism", 185: "Cooking", 186: "Mining", 197: "Tailoring",
               202: "Engineering", 333: "Enchanting", 356: "Fishing", 393: "Skinning"}


def lua(value):
    # Lua 5.1 accepts UTF-8 bytes; JSON's Unicode escapes are not Lua escapes.
    return json.dumps(value, ensure_ascii=False).replace("\\/", "/")


def generate(tables):
    names = {int(r["ID"]): r["Name_lang"] for r in tables["SpellName"]}
    items = {int(r["ID"]): r for r in tables["ItemSparse"]}
    reagents = {}
    for r in tables["SpellReagents"]:
        mats = []
        for i in range(8):
            item, count = int(r[f"Reagent_{i}"]), int(r[f"ReagentCount_{i}"])
            if item > 0 and count > 0:
                mats.append((item, count))
        reagents[int(r["SpellID"])] = mats
    effects = collections.defaultdict(list)
    for r in tables["SpellEffect"]:
        if r["Effect"] == "24" and r["DifficultyID"] == "0" and int(r["EffectItemType"]) > 0:
            effects[int(r["SpellID"])].append(r)
    # Formula/pattern requirements can be higher than the client's minimum craft rank.
    learning = {}
    for r in items.values():
        for prefix in ("Recipe: ", "Plans: ", "Schematic: ", "Pattern: ", "Formula: "):
            if r["Display_lang"].startswith(prefix) and int(r["RequiredSkillRank"]) > 0:
                key = (int(r["RequiredSkill"]), r["Display_lang"][len(prefix):].casefold())
                learning[key] = min(learning.get(key, 9999), int(r["RequiredSkillRank"]))
    rows, seen, omitted = [], set(), collections.Counter()
    for a in tables["SkillLineAbility"]:
        prof, rid = int(a["SkillLine"]), int(a["Spell"])
        if prof not in PROFESSIONS or (prof, rid) in seen:
            continue
        seen.add((prof, rid))
        creates = effects.get(rid, [])
        if len(creates) != 1:
            omitted["no single create-item effect"] += 1
            continue
        e = creates[0]
        out = int(e["EffectItemType"])
        if out not in items or rid not in names or not reagents.get(rid):
            omitted["missing name, output or fixed item reagents"] += 1
            continue
        # Scaling/variable/server-generated recipes cannot be priced as a fixed craft.
        if float(e["Variance"]) != 0 or float(e["EffectRealPointsPerLevel"]) != 0:
            omitted["variable output"] += 1
            continue
        quantity = max(1, float(e["EffectBasePointsF"]))
        if quantity != int(quantity):
            omitted["fractional output"] += 1
            continue
        row = dict(id=rid, prof=PROFESSIONS[prof], skill=int(a["MinSkillLineRank"]),
                   out=out, low=int(quantity), high=int(quantity), n=names[rid],
                   r=reagents[rid], sell=int(items[out]["SellPrice"]),
                   learn=learning.get((prof, names[rid].casefold())))
        if row["skill"] > 300:
            omitted["above skill 300"] += 1
            continue
        rows.append(row)
    rows.sort(key=lambda r: (r["prof"], r["id"]))
    return rows, items, omitted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=pathlib.Path,
                        default=pathlib.Path(tempfile.gettempdir()) / "fl-forever-public")
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parent.parent
    manifest_path = repo / "tools" / "forever-crafts-source.json"
    pinned = json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    tables, manifest = {}, dict(build=BUILD, date=DATE, source="https://wago.tools", tables={})
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    for name in TABLES:
        path = args.cache_dir / (name + ".csv")
        url = f"https://wago.tools/db2/{name}/csv?version={BUILD}"
        if not path.exists():
            if args.offline:
                raise SystemExit(f"Missing cached table: {path}")
            request = urllib.request.Request(url, headers={"User-Agent": "ForeverLedger-Data/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                path.write_bytes(response.read())
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if pinned and pinned["tables"][name]["sha256"] != digest:
            raise SystemExit(f"{name}: snapshot differs from the pinned source; review a new build explicitly")
        manifest["tables"][name] = dict(url=url, sha256=digest, bytes=len(raw))
        tables[name] = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))
    rows, items, omitted = generate(tables)
    header = ["local _, ns = ...", "", "-- Generated by tools/build-forever-crafts.py; do not edit by hand.",
              f"-- Wago public CSVs, Forever {BUILD}, read {DATE}; tools/forever-crafts-source.json pins inputs.",
              "-- Factual client data, copyright Blizzard; not another addon's code or guide text.",
              "-- Source access/limits: tools/FOREVER_DATA_SOURCES.md. Availability and server procs unconfirmed.",
              "-- id=craft spell, skill=client minimum craft rank (NOT a trainer learning requirement);",
              "-- learn=recipe item's learning requirement where one is published. low/high=fixed client output.",
              "-- Captured recipes override these per recipe; Classic fills routes absent from both sources.",
              f"local SOURCE, BUILD = \"https://wago.tools\", \"{BUILD}\"", "ns.FOREVER_CRAFTS = {"]
    wanted = set()
    for r in rows:
        wanted.add(r["out"])
        wanted.update(i for i, _ in r["r"])
        mats = "{ " + ", ".join("{ %d, %d }" % m for m in r["r"]) + " }"
        learn = f", learn = {r['learn']}" if r["learn"] is not None else ""
        header.append(f"  {{ id = {r['id']}, prof = {lua(r['prof'])}, skill = {r['skill']}, out = {r['out']}, low = {r['low']}, high = {r['high']}, sell = {r['sell']}, n = {lua(r['n'])}, r = {mats}, source = SOURCE, build = BUILD{learn} }},")
    header.extend(["}", "", "-- Fallback names only: live/cached localized item names always win.", "ns.FOREVER_ITEM_NAMES = {"])
    for i in sorted(wanted):
        if i in items and items[i]["Display_lang"]:
            header.append(f"  [{i}] = {lua(items[i]['Display_lang'])},")
    header.extend(["}", "", "-- ItemSparse.Flags[0] 0x8000: NoDisenchant, same pinned client build.",
                   "ns.FOREVER_NO_DISENCHANT = {"])
    for i, item in sorted(items.items()):
        if (int(item["Flags_0"]) // 32768) % 2:
            header.append(f"  [{i}] = true,")
    header.extend(["}", ""])
    (repo / "ForeverCrafts.lua").write_text("\n".join(header), encoding="utf-8", newline="\n")
    manifest["counts"] = dict(collections.Counter(r["prof"] for r in rows))
    manifest["omitted"] = dict(omitted)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(rows)} recipes: {manifest['counts']}; omitted {dict(omitted)}")


if __name__ == "__main__":
    main()
