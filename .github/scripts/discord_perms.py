# Discord server permissions as a file (owner, October 1: "tell Claude the experience,
# Claude edits the settings"). Modes:
#   report  every role's server-wide permissions and every category/channel's
#           overrides, in plain words, and whether each channel is synced
#   plan    what "apply" would change to match discord-bot/permissions.json
#   apply   make those changes
# The bot needs Administrator (the "Bot admin" role) while this runs.
# Env: DISCORD_BOT_TOKEN, GUILD_ID; argv: mode.
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://discord.com/api/v10"
GUILD = os.environ["GUILD_ID"]
CONFIG = "discord-bot/permissions.json"

# Permission names used in the file and the report (Discord's bit numbers).
BITS = {
    "Create Invite": 0, "Kick Members": 1, "Ban Members": 2, "Administrator": 3,
    "Manage Channels": 4, "Manage Server": 5, "Add Reactions": 6, "View Audit Log": 7,
    "Priority Speaker": 8, "Video": 9, "View Channel": 10, "Send Messages / Create Posts": 11,
    "Send TTS Messages": 12, "Manage Messages": 13, "Embed Links": 14, "Attach Files": 15,
    "Read Message History": 16, "Mention @everyone and All Roles": 17, "Use External Emojis": 18,
    "View Server Insights": 19, "Connect": 20, "Speak": 21, "Mute Members": 22,
    "Deafen Members": 23, "Move Members": 24, "Use Voice Activity": 25, "Change Nickname": 26,
    "Manage Nicknames": 27, "Manage Roles / Permissions": 28, "Manage Webhooks": 29,
    "Manage Expressions": 30, "Use Application Commands": 31, "Request to Speak": 32,
    "Manage Events": 33, "Manage Threads / Posts": 34, "Create Public Threads": 35,
    "Create Private Threads": 36, "Use External Stickers": 37,
    "Send Messages in Threads / Posts": 38, "Use Activities": 39, "Timeout Members": 40,
    "Use Soundboard": 42, "Create Expressions": 43, "Create Events": 44,
    "Use External Sounds": 45, "Send Voice Messages": 46, "Create Polls": 49,
    "Use External Apps": 50,
}
TYPES = {0: "text", 2: "voice", 4: "category", 5: "announcement", 13: "stage", 15: "forum", 16: "media"}


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bot " + os.environ["DISCORD_BOT_TOKEN"],
                                          "Content-Type": "application/json",
                                          "User-Agent": "DiscordBot (forever-ledger, 1.0)"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} -> {e.code}: {e.read().decode()[:300]}")


def names(bits):
    bits = int(bits)
    return [n for n, b in BITS.items() if bits & (1 << b)]


def to_bits(list_of_names):
    total = 0
    for n in list_of_names:
        if n not in BITS:
            raise SystemExit(f"Unknown permission name in {CONFIG}: {n!r}")
        total |= 1 << BITS[n]
    return str(total)


def load():
    roles = {r["id"]: r for r in call("GET", f"/guilds/{GUILD}/roles")}
    channels = call("GET", f"/guilds/{GUILD}/channels")
    return roles, channels


def who(ow, roles, members):
    if ow["type"] == 0:
        r = roles.get(ow["id"])
        return "@everyone" if ow["id"] == GUILD else (r["name"] if r else ow["id"])
    return "member " + members.get(ow["id"], ow["id"])


def report():
    roles, channels = load()
    members = {}
    print("=== Roles (server-wide permissions, highest first) ===")
    for r in sorted(roles.values(), key=lambda r: -r["position"]):
        tag = " [bot's own role]" if r.get("managed") else ""
        print(f"- {r['name']}{tag}: {', '.join(names(r['permissions'])) or 'none'}")
    by_parent = {}
    for c in channels:
        by_parent.setdefault(c.get("parent_id"), []).append(c)
    cats = sorted([c for c in channels if c["type"] == 4], key=lambda c: c["position"])

    def overrides(c):
        out = []
        for ow in c.get("permission_overwrites", []):
            a, d = names(ow["allow"]), names(ow["deny"])
            if a or d:
                out.append(f"    {who(ow, roles, members)}: " +
                           "; ".join(filter(None, [("allow " + ", ".join(a)) if a else "", ("deny " + ", ".join(d)) if d else ""])))
        return out

    def same(a, b):
        key = lambda c: sorted((o["id"], o["allow"], o["deny"]) for o in c.get("permission_overwrites", []))
        return key(a) == key(b)

    print("\n=== Channels ===")
    for c in sorted(by_parent.get(None, []), key=lambda c: c["position"]):
        if c["type"] != 4:
            print(f"#{c['name']} ({TYPES.get(c['type'], c['type'])}, no category)")
            print("\n".join(overrides(c)) or "    (no overrides)")
    for cat in cats:
        print(f"\n[{cat['name']}] category")
        print("\n".join(overrides(cat)) or "    (no overrides)")
        for c in sorted(by_parent.get(cat["id"], []), key=lambda c: c["position"]):
            synced = same(c, cat)
            print(f"  #{c['name']} ({TYPES.get(c['type'], c['type'])}) {'synced with category' if synced else 'NOT synced'}")
            if not synced:
                print("\n".join("  " + l for l in overrides(c)) or "      (no overrides)")


def desired(roles, channels):
    """{channel id: {target id: (allow bits, deny bits)}} from the config file."""
    cfg = json.load(open(CONFIG, encoding="utf-8"))
    by_name = {r["name"]: r["id"] for r in roles.values()}
    by_name["@everyone"] = GUILD

    def resolve(block):
        out = {}
        for target, perms in block.items():
            if target not in by_name:
                raise SystemExit(f"Unknown role in {CONFIG}: {target!r}")
            out[by_name[target]] = (to_bits(perms.get("allow", [])), to_bits(perms.get("deny", [])))
        return out

    cats = {c["name"]: c for c in channels if c["type"] == 4}
    want = {}
    for cat_name, spec in cfg.get("categories", {}).items():
        if cat_name not in cats:
            raise SystemExit(f"No category named {cat_name!r}")
        cat = cats[cat_name]
        base = resolve(spec.get("permissions", {}))
        want[cat["id"]] = base
        for c in channels:
            if c.get("parent_id") == cat["id"]:
                extra = resolve(spec.get("channels", {}).get(c["name"], {}))
                merged = dict(base)
                merged.update(extra)
                want[c["id"]] = merged
    return want


def create_missing(roles, channels, apply):
    """Channels listed under a category's "create" that don't exist yet: made (as text,
    announcement or forum channels) with the category's permissions."""
    cfg = json.load(open(CONFIG, encoding="utf-8"))
    kinds = {"text": 0, "announcement": 5, "forum": 15}
    cats = {c["name"]: c for c in channels if c["type"] == 4}
    made = 0
    for cat_name, spec in cfg.get("categories", {}).items():
        cat = cats.get(cat_name)
        for ch in spec.get("create", []):
            if cat and any(c["name"] == ch["name"] and c.get("parent_id") == cat["id"] for c in channels):
                continue
            made += 1
            print(f"[{cat_name}]: create #{ch['name']} ({ch.get('type', 'text')})" + (f": {ch['topic']}" if ch.get("topic") else ""))
            if apply and cat:
                call("POST", f"/guilds/{GUILD}/channels", {
                    "name": ch["name"], "type": kinds[ch.get("type", "text")], "parent_id": cat["id"],
                    "topic": ch.get("topic", ""),
                    "permission_overwrites": [{"id": o["id"], "type": o["type"], "allow": o["allow"], "deny": o["deny"]}
                                              for o in cat.get("permission_overwrites", [])],
                })
    return made


def plan_or_apply(apply):
    roles, channels = load()
    if create_missing(roles, channels, apply) and apply:
        roles, channels = load()                 # include the new channels below
    want = desired(roles, channels)
    by_id = {c["id"]: c for c in channels}
    changes = 0
    for cid, targets in want.items():
        c = by_id[cid]
        have = {o["id"]: (o["allow"], o["deny"], o["type"]) for o in c.get("permission_overwrites", [])}
        label = ("[" + c["name"] + "]") if c["type"] == 4 else "#" + c["name"]
        for tid, (allow, deny) in targets.items():
            if have.get(tid, ("0", "0", 0))[:2] != (allow, deny):
                changes += 1
                tname = "@everyone" if tid == GUILD else roles[tid]["name"]
                print(f"{label}: {tname} -> allow {', '.join(names(allow)) or 'nothing'}; deny {', '.join(names(deny)) or 'nothing'}")
                if apply:
                    call("PUT", f"/channels/{cid}/permissions/{tid}", {"allow": allow, "deny": deny, "type": 0})
        for tid, (_, _, typ) in have.items():
            if tid not in targets:
                changes += 1
                tname = "@everyone" if tid == GUILD else (roles[tid]["name"] if tid in roles else tid)
                print(f"{label}: remove the override for {tname}")
                if apply:
                    call("DELETE", f"/channels/{cid}/permissions/{tid}")
    print(f"\n{changes} change(s) {'made' if apply else 'planned'}.")


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "report":
        report()
    else:
        plan_or_apply(mode == "apply")
