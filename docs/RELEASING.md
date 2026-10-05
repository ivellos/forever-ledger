# Releasing a new version

Version numbers look like `MAJOR.MINOR.PATCH`, for example `0.2.1`.

- **PATCH** (0.2.0 → 0.2.1): bug fixes only.
- **MINOR** (0.2.1 → 0.3.0): new features.
- **MAJOR** (0.x → 1.0.0): the first version you'd call finished, or a change that breaks saved data.

While the version starts with `0.`, GitHub marks releases as pre-releases.

## Steps

1. In `CHANGELOG.md`, rename `## [Unreleased]` to the new version and date, for example `## [0.2.0] - 2026-10-05`, then add a fresh empty `## [Unreleased]` above it.
2. Under the new version, add a `### Highlights` list: 5 to 7 short bullets like `- + **Deals tab**: listings well below their usual price, with why each one is a deal`. This becomes the Discord announcement; the rest of the notes are counted ("Plus 13 more changes and 15 bug fixes").
   Start each bullet with its change mark, the same everywhere we post changes (the game's What's new, Discord, the changelog on GitHub, CurseForge and Wago): `Δ` a big change, `+` something new, `~` a change, `✓` a fix. Big changes first. On Discord the marks show as the server's own emojis (the icons in `docs/images/changes`, uploaded as `fl_major`, `fl_new`, `fl_changed`, `fl_fixed`, with their codes in the repository variables `DISCORD_EMOJI_MAJOR`, `_NEW`, `_CHANGED`, `_FIXED`); without them the text mark stays. Fixed and done Discord threads get the wrench or the plus too.
   Also copy them into `ns.WHATS_NEW` in `Welcome.lua` (plain text, no **bold**, each "Name: text") and set its `version` to the new version: players who update see them in chat once, and the What's new button shows them as a card. Mark each by its kind, like software release notes: `major = true` for the two or three big changes (a bold delta, their own card), plain for something new (a plus), `change = true` for a change (a pencil), `fix = true` for a fix (a wrench); the small ones share an "Also in this version" card. The version number is just text.
3. Commit with the summary `Release 0.2.0` and push.
4. In GitHub Desktop, open the **History** tab, right-click that commit and choose **Create Tag**. Name it `v0.2.0` (with the `v`).
5. Click **Push origin** (or **Push tags**).
6. Open the **Actions** tab on GitHub and wait for "Build release" to turn green, about a minute.
7. Open **Releases**. The new version is there with the zip attached and the changelog notes filled in. The same run uploads it to CurseForge and Wago and posts the announcement in the Discord #announcements channel.

To re-post an announcement or upload an old version again, run "Build release" by hand from the Actions tab with the tag and the boxes you want ("Only show the announcement in the log" previews without posting).

You never edit the version number in the addon files. The release build fills it in from the tag.
