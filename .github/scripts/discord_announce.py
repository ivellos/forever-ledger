# Builds the Discord announcement for a release, in the style the owner picked
# (October 1, like EllesmereUI's update posts): a title line, the main features as
# "**Name**: one line" bullets, a count of the rest and of bug fixes, the link to the
# full notes, and a ping for the updates role if one is set.
#
# The bullets come from the version's "### Highlights" list in CHANGELOG.md (short
# one-liners written when the release is prepared). Without one, the first sentence of
# each Added/Changed entry is used, which reads less well.
# Usage: discord_announce.py <CHANGELOG.md> <version> <notes url> [role id] > payload.json
#
# Change marks (owner, October 5, like the icons in the game's What's new): each
# Highlights line starts with "Δ " (a big change), "+ " (new), "~ " (changed) or "✓ "
# (fixed). On Discord the mark becomes the server's own emoji (docs/images/changes,
# uploaded as fl_major, fl_new, fl_changed, fl_fixed), looked up by name with the bot
# (DISCORD_BOT_TOKEN, GUILD_ID); an emoji that isn't there keeps the text mark.
# DISCORD_EMOJI_MAJOR / _NEW / _CHANGED / _FIXED ("<:fl_new:123...>") override the lookup
# (the code check uses them).
import json
import os
import re
import sys
import urllib.request

MARKS = {"Δ": "major", "+": "new", "~": "changed", "✓": "fixed"}


def server_emojis():
    """{ "fl_new": "<:fl_new:123>", ... } from the Discord server, or {} without the bot."""
    token, guild = os.environ.get("DISCORD_BOT_TOKEN", ""), os.environ.get("GUILD_ID", "")
    if not (token and guild):
        return {}
    try:
        req = urllib.request.Request(f"https://discord.com/api/v10/guilds/{guild}/emojis", headers={
            "Authorization": "Bot " + token, "User-Agent": "DiscordBot (https://github.com/ivellos/forever-ledger, 1.0)"})
        with urllib.request.urlopen(req, timeout=20) as r:
            found = json.load(r)
    except Exception as e:   # (no emojis is fine: the text marks stay)
        print("Couldn't read the server's emojis:", e, file=sys.stderr)
        return {}
    return {e["name"]: f"<{'a' if e.get('animated') else ''}:{e['name']}:{e['id']}>" for e in found}


EMOJIS = server_emojis()
print("Change-mark emojis on the server:", ", ".join(sorted(n for n in EMOJIS if n.startswith("fl_"))) or "none",
      file=sys.stderr)


def bullet(line):
    """A Highlights line as a Discord line: its mark as the emoji (no dash), or "- " before
    an unmarked one."""
    for mark, kind in MARKS.items():
        if line.startswith(mark + " "):
            emoji = os.environ.get("DISCORD_EMOJI_" + kind.upper(), "").strip() or EMOJIS.get("fl_" + kind, "")
            return f"{emoji or mark} {line[len(mark) + 1:]}"
    return "- " + line

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

title = f"Forever Ledger {version} is live on CurseForge, Wago and GitHub"
lines = []
extras = []
if highlights:
    lines.append("Major updates/features include:")
    lines += [bullet(h) for h in highlights]
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

# The announcement sits in an embed (purple bar, linked title, the coin icon); the
# role ping goes in the message text above it, since pings inside embeds don't notify.
description = "\n".join(lines)
if len(description) > 4000:   # Discord's limit for an embed description
    description = description[:3990].rsplit("\n", 1)[0]
embed = {
    "title": title,
    "url": url,
    "color": 0xB9A2FF,
    "description": description,
    "thumbnail": {"url": "https://raw.githubusercontent.com/ivellos/forever-ledger/main/docs/images/icon.png"},
}
content = ""
if role:
    content = f"<@&{role}>\n*Want a ping when there's an update? Pick the Updates role in Channels & Roles.*"
print(json.dumps({"content": content, "embeds": [embed], "allowed_mentions": {"roles": [role] if role else []}}))
