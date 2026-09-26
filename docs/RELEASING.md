# Releasing a new version

Version numbers look like `MAJOR.MINOR.PATCH`, for example `0.2.1`.

- **PATCH** (0.2.0 → 0.2.1): bug fixes only.
- **MINOR** (0.2.1 → 0.3.0): new features.
- **MAJOR** (0.x → 1.0.0): the first version you'd call finished, or a change that breaks saved data.

While the version starts with `0.`, GitHub marks releases as pre-releases.

## Steps

1. In `CHANGELOG.md`, rename `## [Unreleased]` to the new version and date, for example `## [0.2.0] - 2026-10-05`, then add a fresh empty `## [Unreleased]` above it.
2. Commit with the summary `Release 0.2.0` and push.
3. In GitHub Desktop, open the **History** tab, right-click that commit and choose **Create Tag**. Name it `v0.2.0` (with the `v`).
4. Click **Push origin** (or **Push tags**).
5. Open the **Actions** tab on GitHub and wait for "Build release" to turn green, about a minute.
6. Open **Releases**. The new version is there with the zip attached and the changelog notes filled in.

You never edit the version number in the addon files. The release build fills it in from the tag.
