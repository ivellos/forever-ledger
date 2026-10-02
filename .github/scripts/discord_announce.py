# Builds the Discord announcement for a release, in the style the owner picked
# (October 1, like EllesmereUI's update posts): a title line, the main features as
# "**Name**: one line" bullets, a count of the rest and of bug fixes, the link to the
# full notes, and a ping for the updates role if one is set.
#
# The bullets come from the version's "### Highlights" list in CHANGELOG.md (short
# one-liners written when the release is prepared). Without one, the first sentence of
# each Added/Changed entry is used, which reads less well.
# Usage: discord_announce.py <CHANGELOG.md> <version> <notes url> [role id] > payload.json
import json
import re
import sys

MAX_FEATURES = 7      # bullets shown when falling back to Added/Changed
MAX_BULLET = 170      # characters per fallback bullet

changelog_path, version, url = sys.argv[1], sys.argv[2], sys.argv[3]
role = sys.argv[4].strip() if len(sys.argv) > 4 else ""

# This version's section of the changelog.
sections, current, inside = {}, None, False
for line in open(changelog_path, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("## "):
        inside = line.startswith(f"## [{version}]")
        current = None
        continue
    if not inside:
        continue
    heading = re.match(r"^###\s+(.+)$", line)
    if heading:
        current = heading.group(1).strip().lower()
        sections.setdefault(current, [])
    elif current and line.startswith("- "):
        sections[current].append(line[2:].strip())


def short(text):
    """'Deals tab: listings ... More.' -> '**Deals tab**: listings ...' (first sentence)."""
    label = None
    m = re.match(r"^([^:(]{2,40}):\s+(.*)$", text)
    if m:
        label, text = m.group(1), m.group(2)
    first = re.split(r"(?<=[.!?])\s+", text, maxsplit=1)[0]
    if len(first) > MAX_BULLET:
        first = first[: MAX_BULLET - 3].rsplit(" ", 1)[0] + "..."
    return f"**{label}**: {first}" if label else first


features = sections.get("added", []) + sections.get("changed", [])
fixes = sections.get("fixed", [])
highlights = sections.get("highlights", [])

lines = [f"## Forever Ledger {version} is live on CurseForge, Wago and GitHub"]
extras = []
if highlights:
    lines.append("Major updates/features include:")
    lines += ["- " + h for h in highlights]
    if fixes:
        extras.append(f"{len(fixes)} bug fix{'es' if len(fixes) != 1 else ''}")
    others = len(features) - len(highlights)
    if others > 0:
        extras.insert(0, f"{others} more change{'s' if others != 1 else ''}")
elif features:
    lines.append("Major updates/features include:")
    lines += ["- " + short(t) for t in features[:MAX_FEATURES]]
    more = len(features) - MAX_FEATURES
    if more > 0:
        extras.append(f"{more} more new feature{'s' if more != 1 else ''}")
    if fixes:
        extras.append(f"{len(fixes)} bug fix{'es' if len(fixes) != 1 else ''}")
if extras:
    lines.append("- Plus " + " and ".join(extras) + ".")
lines += ["", "**Full patch notes:**", url]
if role:
    lines += ["", f"<@&{role}>", "*Want a ping when there's an update? Pick the Updates role in Channels & Roles.*"]

content = "\n".join(lines)
if len(content) > 2000:   # Discord's limit for a message
    content = content[:1990].rsplit("\n", 1)[0]
print(json.dumps({"content": content, "allowed_mentions": {"roles": [role] if role else []}}))
