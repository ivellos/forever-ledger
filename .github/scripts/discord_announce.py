# Builds the Discord announcement for a release from its changelog notes, in the style
# the owner picked (October 1, like EllesmereUI's update posts): a title line, the main
# features as "**Name**: one line" bullets, a count of the rest and of bug fixes, the link
# to the full notes, and a ping for the updates role if one is set.
# Usage: discord_announce.py <notes.md> <version> <release url> [role id]  > payload.json
import json
import re
import sys

MAX_FEATURES = 7      # bullets shown; the rest are counted
MAX_BULLET = 170      # characters per bullet

notes_path, version, url = sys.argv[1], sys.argv[2], sys.argv[3]
role = sys.argv[4].strip() if len(sys.argv) > 4 else ""

sections, current = {}, None
for line in open(notes_path, encoding="utf-8"):
    line = line.rstrip("\n")
    heading = re.match(r"^###\s+(.+)$", line)
    if heading:
        current = heading.group(1).strip().lower()
        sections.setdefault(current, [])
    elif current and line.startswith("- "):
        sections[current].append(line[2:].strip())


def short(text):
    """'Deals tab: listings ... More.' -> '**Deals tab**: listings ...' (first sentence)."""
    label = None
    m = re.match(r"^([^:]{2,60}):\s+(.*)$", text)
    if m:
        label, text = m.group(1), m.group(2)
    first = re.split(r"(?<=[.!?])\s+", text, maxsplit=1)[0]
    if len(first) > MAX_BULLET:
        first = first[: MAX_BULLET - 3].rsplit(" ", 1)[0] + "..."
    first = first[0].upper() + first[1:] if first else first
    return f"**{label}**: {first}" if label else first


features = sections.get("added", []) + sections.get("changed", [])
fixes = sections.get("fixed", [])
lines = [f"## Forever Ledger {version} is live on CurseForge, Wago and GitHub"]
if features:
    lines.append("Major updates/features include:")
    for text in features[:MAX_FEATURES]:
        lines.append("- " + short(text))
more = len(features) - MAX_FEATURES
extras = []
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
payload = {"content": content, "allowed_mentions": {"roles": [role] if role else []}}
print(json.dumps(payload))
