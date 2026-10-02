// Forever Ledger Discord bot: the /bug and /idea forms.
//
// Runs on Cloudflare Workers (free plan), deployed by .github/workflows/discord-bot.yml.
// Discord sends every slash command and form here (the app's Interactions Endpoint URL).
//   /bug, /idea  -> a pop-up form with required fields
//   form sent    -> a post in #bug-reports or #feature-requests, written by the bot,
//                   naming (and mentioning) the person who filled it in; the existing
//                   GitHub sync (.github/scripts/discord_sync.py) turns it into an issue.
// Every request is checked against the app's public key, as Discord requires.
// Settings in wrangler.toml; the bot token is a Worker secret (DISCORD_BOT_TOKEN).

const API = "https://discord.com/api/v10";
const EPHEMERAL = 64;

// Forms. Discord allows at most 5 text fields per form.
const FORMS = {
  bug: {
    title: "Report a bug",
    forum: "BUG_FORUM",
    tag: "New",
    fields: [
      { id: "title", label: "Short title", style: 1, required: true, max: 90, placeholder: "e.g. Deals tab is empty after a full scan" },
      { id: "version", label: "Addon version (top of the /fl window)", select: "versions" },
      { id: "what", label: "What happened?", style: 2, required: true, max: 1500 },
      { id: "expected", label: "What did you expect instead?", style: 2, required: false, max: 600 },
      { id: "details", label: "How to make it happen, error text, /fl api", style: 2, required: false, max: 1800,
        placeholder: "Steps, the BugSack error or /fl api output. Add screenshots by replying in the post." },
    ],
  },
  idea: {
    title: "Suggest a feature",
    forum: "IDEA_FORUM",
    tag: "Idea",
    fields: [
      { id: "title", label: "Short title", style: 1, required: true, max: 90, placeholder: "e.g. Undercut alerts for my auctions" },
      { id: "idea", label: "What would you like?", style: 2, required: true, max: 1500 },
      { id: "why", label: "How would you use it / what does it solve?", style: 2, required: true, max: 1000 },
    ],
  },
};

const ALIASES = { feature: "idea" };

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

async function verify(request, body, publicKey) {
  const sig = request.headers.get("X-Signature-Ed25519");
  const ts = request.headers.get("X-Signature-Timestamp");
  if (!sig || !ts) return false;
  const data = new TextEncoder().encode(ts + body);
  for (const alg of [{ name: "Ed25519" }, { name: "NODE-ED25519", namedCurve: "NODE-ED25519" }]) {
    try {
      const key = await crypto.subtle.importKey("raw", hexToBytes(publicKey), alg, false, ["verify"]);
      return await crypto.subtle.verify(alg, key, hexToBytes(sig), data);
    } catch (e) { /* try the older algorithm name */ }
  }
  return false;
}

async function discord(env, method, path, body) {
  const r = await fetch(API + path, {
    method,
    headers: { Authorization: "Bot " + env.DISCORD_BOT_TOKEN, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

// The last 5 releases from GitHub, newest first, kept for an hour (Cloudflare's cache),
// so /bug opens fast and new releases show up by themselves. Falls back to none.
const RELEASES = "https://api.github.com/repos/ivellos/forever-ledger/releases?per_page=5";
async function recentVersions() {
  const cache = caches.default;
  const key = new Request(RELEASES);
  let r = await cache.match(key);
  if (!r) {
    try {
      const live = await fetch(RELEASES, { headers: { "User-Agent": "forever-ledger-bot", Accept: "application/vnd.github+json" } });
      if (!live.ok) return [];
      r = new Response(await live.text(), { headers: { "Content-Type": "application/json", "Cache-Control": "max-age=3600" } });
      await cache.put(key, r.clone());
    } catch (e) {
      return [];
    }
  }
  try {
    return (await r.json()).map((x) => (x.tag_name || "").replace(/^v/, "")).filter(Boolean).slice(0, 5);
  } catch (e) {
    return [];
  }
}

// Forms use Discord's newer layout: each field in a Label, so a dropdown can sit among
// the text boxes.
function modal(kind, versions) {
  const f = FORMS[kind];
  return {
    type: 9,
    data: {
      custom_id: kind + "_form",
      title: f.title,
      components: f.fields.map((x) => {
        if (x.select === "versions") {
          const options = versions.map((v, i) => ({ label: v + (i === 0 ? " (latest)" : ""), value: v, default: i === 0 }));
          options.push({ label: "Newer test build", value: "test build" });
          options.push({ label: "Older / not sure", value: "older or not sure", default: versions.length === 0 });
          return { type: 18, label: x.label, component: { type: 3, custom_id: x.id, options, required: true } };
        }
        return {
          type: 18,
          label: x.label,
          component: { type: 4, custom_id: x.id, style: x.style, required: x.required, max_length: x.max, placeholder: x.placeholder },
        };
      }),
    },
  };
}

// Answers come back as Labels holding one field each (or older action rows).
function formValues(data) {
  const v = {};
  const take = (c) => {
    if (!c || !c.custom_id) return;
    v[c.custom_id] = c.values ? c.values.join(", ") : (c.value || "").trim();
  };
  for (const row of data.components || []) {
    take(row.component);
    for (const c of row.components || []) take(c);
  }
  return v;
}

function postText(kind, v, user) {
  const who = `${user.global_name || user.username} (<@${user.id}>)`;
  const parts = [];
  if (kind === "bug") {
    parts.push(`**Reported by** ${who}`, `**Addon version:** ${v.version}`, "", "**What happened**", v.what);
    if (v.expected) parts.push("", "**Expected**", v.expected);
    if (v.details) parts.push("", "**How to make it happen / error text**", v.details);
  } else {
    parts.push(`**Suggested by** ${who}`, "", "**The idea**", v.idea, "", "**How it would be used**", v.why);
  }
  return parts.join("\n").slice(0, 1990);
}

// After the form: make the forum post, then edit the private "working on it" reply.
async function submit(env, interaction, kind) {
  const f = FORMS[kind];
  const v = formValues(interaction.data);
  const user = (interaction.member && interaction.member.user) || interaction.user;
  const followup = `/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`;
  try {
    const forumId = env[f.forum];
    const forum = await discord(env, "GET", `/channels/${forumId}`);
    const tag = (forum.available_tags || []).find((t) => t.name === f.tag);
    const post = {
      name: (v.title || f.title).slice(0, 100),
      applied_tags: tag ? [tag.id] : [],
      message: { content: postText(kind, v, user), allowed_mentions: { users: [user.id] } },
    };
    let thread;
    try {
      thread = await discord(env, "POST", `/channels/${forumId}/threads`, post);
    } catch (e) {
      // A moderator-only tag needs Manage Threads; post without it rather than fail.
      if (!post.applied_tags.length) throw e;
      console.log("Posting with the tag failed, trying without:", e.message);
      thread = await discord(env, "POST", `/channels/${forumId}/threads`, { ...post, applied_tags: [] });
    }
    await discord(env, "PATCH", followup, {
      content: `Thanks! Your ${kind === "bug" ? "bug report" : "idea"} is posted: <#${thread.id}>\n` +
        "You can add screenshots by replying there. It goes to our GitHub tracker within about 15 minutes.",
    });
  } catch (e) {
    console.log("Form submit failed:", e.message);
    // Only the person who sent the form sees this; the detail helps fix it.
    const detail = (e.message || "").replace(/^[A-Z]+ \/[^ ]+ -> /, "").slice(0, 300);
    await discord(env, "PATCH", followup, {
      content: "Sorry, something went wrong posting that. Please try again in a minute, or ask in #help.\n" +
        "`" + detail.replace(/`/g, "'") + "`",
    }).catch(() => {});
  }
}

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") return new Response("Forever Ledger bot is running.", { status: 200 });
    const body = await request.text();
    if (!(await verify(request, body, env.PUBLIC_KEY))) return new Response("Bad signature", { status: 401 });
    const i = JSON.parse(body);

    if (i.type === 1) return json({ type: 1 });   // Discord's check that we're here

    if (i.type === 2) {                            // a slash command
      // /feature is the same form as /idea (the forum is called feature-request).
      const name = ALIASES[i.data && i.data.name] || (i.data && i.data.name);
      if (FORMS[name]) return json(modal(name, name === "bug" ? await recentVersions() : []));
      return json({ type: 4, data: { content: "Unknown command.", flags: EPHEMERAL } });
    }

    if (i.type === 5) {                            // a form was sent
      const kind = (i.data.custom_id || "").replace(/_form$/, "");
      if (!FORMS[kind]) return json({ type: 4, data: { content: "Unknown form.", flags: EPHEMERAL } });
      ctx.waitUntil(submit(env, i, kind));
      return json({ type: 5, data: { flags: EPHEMERAL } });   // "thinking...", only they see it
    }

    return json({ type: 4, data: { content: "Not supported.", flags: EPHEMERAL } });
  },
};
