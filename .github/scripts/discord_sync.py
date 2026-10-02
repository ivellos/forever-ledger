# Syncs the Discord forums #bug-reports and #feature-requests with GitHub issues.
#   poll:   each new forum post becomes a GitHub issue (label bug / enhancement); the
#           bot replies in the thread with the link and adds the "On GitHub" tag.
#   issue:  when an issue that came from Discord is closed or reopened, the bot posts
#           in the thread and sets its status tag (Fixed / Can't reproduce for bugs,
#           Done / Not planned for ideas).
# Runs in GitHub Actions (.github/workflows/discord-sync.yml); standard library only.
# Env: DISCORD_BOT_TOKEN, GITHUB_TOKEN, GITHUB_REPOSITORY, GUILD_ID, BUG_FORUM, IDEA_FORUM,
#      and for "issue": GITHUB_EVENT_PATH.
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DISCORD = "https://discord.com/api/v10"
GITHUB = "https://api.github.com"
REPO = os.environ["GITHUB_REPOSITORY"]
GUILD = os.environ["GUILD_ID"]
FORUMS = {os.environ["BUG_FORUM"]: "bug", os.environ["IDEA_FORUM"]: "idea"}
LABELS = {"bug": "bug", "idea": "enhancement"}
MARKER = "Discord thread ID: "
ON_GITHUB = "On GitHub"
# Status tags set when an issue closes, by kind and close reason; and the opening tags
# removed at that point.
STATUS = {
    ("bug", "completed"): "Fixed", ("bug", "not_planned"): "Can't reproduce",
    ("idea", "completed"): "Done", ("idea", "not_planned"): "Not planned",
}
OPENING = {"New", "Idea", "Confirmed", "Planned", "In progress"}


def request(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(3):
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req) as r:
                text = r.read().decode()
                return json.loads(text) if text else None
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:      # rate limited: wait and retry
                time.sleep(float(json.loads(e.read().decode()).get("retry_after", 2)) + 0.5)
                continue
            raise RuntimeError(f"{method} {url} -> {e.code}: {e.read().decode()[:300]}")


def discord(method, path, body=None):
    return request(method, DISCORD + path, {
        "Authorization": "Bot " + os.environ["DISCORD_BOT_TOKEN"],
        "Content-Type": "application/json",
        "User-Agent": f"DiscordBot (https://github.com/{REPO}, 1.0)",
    }, body)


def github(method, path, body=None):
    return request(method, GITHUB + path, {
        "Authorization": "Bearer " + os.environ["GITHUB_TOKEN"],
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": REPO,
    }, body)


def forum_tags(forum_id):
    """{tag name: tag id} for a forum channel."""
    return {t["name"]: t["id"] for t in discord("GET", f"/channels/{forum_id}").get("available_tags", [])}


def already_on_github(thread_id):
    q = urllib.parse.quote(f'repo:{REPO} "{MARKER}{thread_id}" in:body')
    return github("GET", f"/search/issues?q={q}").get("total_count", 0) > 0


def new_threads():
    """Forum posts in our two forums, active or recently archived."""
    threads = {}
    for t in discord("GET", f"/guilds/{GUILD}/threads/active").get("threads", []):
        if t.get("parent_id") in FORUMS:
            threads[t["id"]] = t
    for forum in FORUMS:
        for t in discord("GET", f"/channels/{forum}/threads/archived/public?limit=50").get("threads", []):
            threads.setdefault(t["id"], t)
    return threads.values()


def poll():
    tags = {forum: forum_tags(forum) for forum in FORUMS}
    made = 0
    for t in new_threads():
        forum, kind = t["parent_id"], FORUMS[t["parent_id"]]
        on_github = tags[forum].get(ON_GITHUB)
        applied = t.get("applied_tags", [])
        if on_github and on_github in applied:
            continue
        if already_on_github(t["id"]):       # issue made but tagging failed last time
            continue
        try:
            first = discord("GET", f"/channels/{t['id']}/messages/{t['id']}")
        except RuntimeError:
            first = {}
        author = (first.get("author") or {}).get("global_name") or (first.get("author") or {}).get("username") or "someone"
        # Posts from the /bug and /idea forms are written by the bot and name the
        # player themselves ("Reported by ..."), so don't credit the bot.
        from_form = (first.get("author") or {}).get("bot")
        text = (first.get("content") or "").strip() or "(no text)"
        images = [a["url"] for a in first.get("attachments", [])]
        link = f"https://discord.com/channels/{GUILD}/{t['id']}"
        body = "\n\n".join(filter(None, [
            text,
            "\n".join(f"![attachment]({u})" for u in images),
            f"---\nPosted in Discord #{'bug-reports' if kind == 'bug' else 'feature-requests'}"
            + ("" if from_form else f" by **{author}**") + f": {link}",
            f"{MARKER}{t['id']}",
        ]))
        issue = github("POST", f"/repos/{REPO}/issues", {"title": t["name"][:250], "body": body, "labels": [LABELS[kind]]})
        discord("POST", f"/channels/{t['id']}/messages", {
            "content": f"Thanks! This is now tracked on GitHub as #{issue['number']}: <{issue['html_url']}>\n"
                       f"You'll get an update here when it's {'fixed' if kind == 'bug' else 'done'}.",
            "allowed_mentions": {"parse": []},
        })
        if on_github:
            discord("PATCH", f"/channels/{t['id']}", {"applied_tags": (applied + [on_github])[-5:]})
        made += 1
        print(f"Thread {t['id']} '{t['name']}' -> issue #{issue['number']}")
    print(f"Done: {made} new issue(s).")


# (The #help sticky notice is StickyBot's job since October 1, not this script's.)


def issue_event():
    event = json.load(open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8"))
    issue, action = event["issue"], event["action"]
    m = re.search(re.escape(MARKER) + r"(\d+)", issue.get("body") or "")
    if not m:
        print("Not from Discord, nothing to do.")
        return
    thread_id = m.group(1)
    thread = discord("GET", f"/channels/{thread_id}")
    forum = thread.get("parent_id")
    kind = FORUMS.get(forum, "bug")
    tags = forum_tags(forum) if forum else {}
    by_id = {v: k for k, v in tags.items()}
    keep = [tid for tid in thread.get("applied_tags", []) if by_id.get(tid) not in OPENING and by_id.get(tid) not in STATUS.values()]
    if action == "closed":
        reason = issue.get("state_reason") or "completed"
        status = STATUS.get((kind, reason))
        if reason == "completed":
            text = ("Fixed on GitHub: the fix will be in the next release." if kind == "bug"
                    else "Done on GitHub: it will be in the next release.")
        else:
            text = ("Closed on GitHub: we couldn't reproduce it. Reply here if it still happens and we'll look again."
                    if kind == "bug" else "Closed on GitHub: not planned for now. Thanks for the idea!")
        if status and status in tags:
            keep.append(tags[status])
    else:
        text = "Reopened on GitHub: we're looking at this again."
        opening = "New" if kind == "bug" else "Idea"
        if opening in tags:
            keep.append(tags[opening])
    discord("POST", f"/channels/{thread_id}/messages", {
        "content": f"{text} <{issue['html_url']}>", "allowed_mentions": {"parse": []},
    })
    discord("PATCH", f"/channels/{thread_id}", {"applied_tags": keep[-5:]})
    print(f"Issue #{issue['number']} {action} -> thread {thread_id}")


def comment_event():
    """A comment on an issue that came from Discord is posted in its thread, so the
    player sees questions and updates (bots' comments are left out)."""
    event = json.load(open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8"))
    issue, comment = event["issue"], event["comment"]
    if (comment.get("user") or {}).get("type") == "Bot":
        return
    m = re.search(re.escape(MARKER) + r"(\d+)", issue.get("body") or "")
    if not m:
        print("Not from Discord, nothing to do.")
        return
    text = (comment.get("body") or "").strip()
    if len(text) > 1800:
        text = text[:1800].rsplit("\n", 1)[0] + "\n..."
    discord("POST", f"/channels/{m.group(1)}/messages", {
        "content": f"**Update from the developer:**\n{text}\n<{comment['html_url']}>",
        "allowed_mentions": {"parse": []},
    })
    print(f"Comment on #{issue['number']} -> thread {m.group(1)}")


if __name__ == "__main__":
    {"poll": poll, "issue": issue_event, "comment": comment_event}[sys.argv[1]]()
