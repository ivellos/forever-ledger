# Forever reference data

Checked November 14, 2026. No addon code, guide prose, account uploads or private
saved data is copied into the generated catalog. Client facts remain Blizzard's.

## Recipes and item eligibility

`build-forever-crafts.py` joins Wago's **1.60.1.70938** public CSVs. Its source
manifest pins the URL, SHA-256 and size of each input. Run with Python 3:

```
python tools/build-forever-crafts.py
python tools/build-forever-crafts.py --offline --cache-dir <download-folder>
```

The generator rejects a cache that differs from the manifest. To adopt another
build, review the build constant and a new manifest together; do not silently
refresh an old build. No downloader runs in the game.

Each row retains its craft spell ID, profession, `skill` (the client's minimum
craft rank), output, fixed quantity range, reagents, name, vendor value, source
and build. **Craft rank is not necessarily the skill needed to learn a recipe.**
`learn` supplies the latter when a matching recipe item publishes it. Training
requirements and server availability are not guaranteed by these tables.
Names and vendor values are fallbacks; the game's own information wins, including
a known zero/no-sale result. SkillLineAbility and SpellEffect supply fixed item
crafts only: enchants without an item output, recipes without fixed item reagents,
multiple outputs, scaling and variable effects are not guessed. The manifest
counts omissions. The catalog includes current replacements for Classic recipe
IDs as well as new recipes. All professions merges per recipe/route, not per
profession: captured data first, this catalog next, Classic last.

ItemSparse flag `0x8000` supplies NoDisenchant exclusions. The flag agrees with
the confirmed crafted-wand exclusions; being made by Enchanting alone is not a
reason to exclude an item. Flag meaning cross-checked against the public
[TrinityCore item flags](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/game/Entities/Item/ItemTemplate.h).

## Disenchant model and limits

- [Wago ItemDisenchantLoot CSV](https://wago.tools/db2/ItemDisenchantLoot/csv?version=1.60.1.70938):
  class/quality/level eligibility, maximum item level 99, no additional skill gate.
  It does **not** contain server loot probabilities or output quantities.
- [WoW-Professions Forever guide](https://www.wow-professions.com/forever/disenchanting-guide):
  material identities/ranges and skill 1. Its levels are required levels, not
  item levels; the implementation's eligibility bands come from the client.
- [ForeverDB's Enchanting page](https://foreverdb.net/profession/enchanting):
  Data from ForeverDB.net. Public numerical ranges/chances, explicitly labeled
  **Classic data**, cross-checked against the guide. No site code or prose copied.
  The site welcomes assistants in robots.txt and permits its data with attribution.
  This is not a claim that its inherited table was tested in Forever.

The public model gives ilvl 21–25 greens a 10% shard chance (armor 75/15/10,
weapons 15/75/10), and ilvl 51+ weapons 22/75/3. Other green bands retain their
listed 75/20/5 or lowest-band 80/20 split. The lowest-band expected values now
equal the displayed chances times the midpoint of the quantity ranges.
The local ilvl 21–30 weapon essence override remains Greater Magic Essence.

Blue items from ilvl 21 have a one-shard estimate. The very rare high-level
crystal tail is omitted: the guide is approximate and the public detailed table
is incomplete. Epic estimates use the public 2–4 shards (ilvl 40–55), one Nexus
Crystal (56–60) and 1–2 crystals (61–99), within current client eligibility bands.
These added models are not marked tested. All ranks of Enchanting count from 1,
also confirmed in game by the owner on November 14.

The 120 locally recorded results are a **check**, not a fitted probability table:
116 greens and four blues, no detected Arcane Salvager. Five ilvl 21–30 green
weapons yielded Greater Magic Essence. Armor materials/ranges have observations
through 35; percentages remain modeled. Three early blues (271206, 271203,
253885, ilvl 15–20) yielded essences, conflicting with the generic shard rule;
early blues therefore remain unknown/unpriced. Staff of Westfall 2042 (ilvl 24)
yielded one Small Glimmering Shard. One Heavy Woolen Gloves 4310 event at ilvl 17
yielded one dust outside the displayed 2–3 range; no band-wide change is inferred.
There are no local epic or Salvager comparisons and no historical cast-time
skill or failed-attempt records. The “observed” marks describe material evidence,
not measured confidence in the advertised probabilities.
Lowest-band armor gave essence in 9/20 cases (45% versus the modeled 20%);
ilvl 21–25 armor gave zero shards in 15 cases versus the public model's 10%.
These small, mixed samples do not establish new population probabilities.

## Access checks and sources not used

| Source | Check and outcome |
|---|---|
| wago.tools | robots.txt and llms.txt explicitly permit `/db2/*/csv` and APIs; used only these routes. Browsing/diff pages excluded. Unavailable exports (403) not bypassed. |
| ForeverEcon | robots allows public pages, excludes `/api/`; public recipes/source pages checked, no additional reuse restriction found there. No API or bulk data imported; client CSVs were more complete. |
| Forever Codex | robots allows public pages; sources page checked. Client facts and Classic-derived data distinguished. No data imported. |
| Everloot | robots allows user-requested public access; terms distinguish CC BY-SA player observations and Blizzard client facts. No uploads, observations or code imported. |
| Wowhead | robots blocks named AI crawlers; excluded from automated extraction for this task. |
| BootyBayBroker | **Skipped**: terms §4 forbid automated extraction without prior written permission. No calculator table imported. |
| Forever Mastery | **Skipped**: legal notice requires permission for reuse beyond quotation. No calculator table imported. |
| WoW-Professions | robots allows this guide path; guide path allowed; linked disclaimer/privacy pages returned 403 and were not bypassed. No permission inferred from those unavailable pages. Only numerical facts used, no prose or guide table copied verbatim. |
| ForeverDB.net | robots explicitly welcomes assistants, points tools to public data with attribution; inspected public numerical table only. No authenticated API, addon files or GPL addon code imported. |
| SKTools | Not read or copied. |

These checks record access decisions for this snapshot, not permission to ignore
future source restrictions. Recheck before updating.
