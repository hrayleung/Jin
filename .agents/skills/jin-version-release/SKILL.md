---
name: jin-version-release
description: Publish a stable Jin release for a user-supplied MAJOR.MINOR.PATCH version by running the repo packaging flow, generating a Sparkle-signed appcast entry, pushing master and the matching tag, and creating the GitHub release. Use when Codex needs to ship a new Jin release, republish an existing version safely, or gather release-note context for that publish flow.
---

# Jin Version Release

Publish a stable Jin release end-to-end.

## Inputs

- Accept exact stable versions only: `MAJOR.MINOR.PATCH`
- Normalize the tag as `v$VERSION`
- Keep release notes in English unless the user explicitly asks for another language
- Use `REPLACE_EXISTING=1` only when the user explicitly wants to republish the same version

## Repo invariants

- Release from `master`
- Require a clean working tree before packaging
- Require `HEAD` to include the latest `origin/master`
- Never publish an unsigned Sparkle appcast entry
- Ship the archive as `Jin-$VERSION.zip`

## Use the bundled script

Run from the repo root.

### 1) Gather release-note context

```bash
bash .agents/skills/jin-version-release/scripts/jin-release.sh context 0.58.1
```

This command fetches tags, finds the previous release tag, writes merged PR data to `/tmp`, and prints the compare URL.

Then create `/tmp/jin-release-notes.md` in this exact shape:

```markdown
## What's Changed
- <bullet 1>
- <bullet 2>

**Full Changelog**: https://github.com/hrayleung/Jin/compare/<PREV_TAG>...v<VERSION>
```

- Use one bullet per merged PR or clearly user-facing change.
- Cross-check the final bullets against the merged PR list before publishing.
- Skip internal-only noise unless it has user impact.

### 2) Publish

```bash
bash .agents/skills/jin-version-release/scripts/jin-release.sh publish 0.58.1 /tmp/jin-release-notes.md
```

Optional environment variables:

- `DRY_RUN=1` — print the publish flow without mutating git, dist, appcast, tags, or GitHub releases
- `REPLACE_EXISTING=1` — delete an existing release/tag before republishing the same version
- `SPARKLE_GENERATE_APPCAST=/path/to/generate_appcast` — override appcast binary discovery

The publish command:

- validates GitHub auth, branch, clean tree, Sparkle key, and appcast tooling
- packages with `JIN_BUNDLE_SHORT_VERSION`
- renames the archive to `dist/Jin-$VERSION.zip`
- verifies bundle version/build metadata
- signs and validates `docs/appcast.xml`
- commits the appcast update with a Lore-format commit message
- tags `v$VERSION`, pushes `master` and the tag, creates the GitHub release, and runs postchecks

## Manual checks before claiming success

After publish, confirm:

- `gh release view v$VERSION` shows the new release and `Jin-$VERSION.zip`
- `docs/appcast.xml` has the first `<item>` for `$VERSION`
- the appcast enclosure URL and asset size match the GitHub release asset

## Failure handling

- Stop on the first failed preflight, signing, or postcheck step.
- If packaging changes `HEAD`, restart from preflight.
- If appcast signing fails, do not tag or publish.
- If release creation fails after pushing the tag, resolve release state before retrying.
- Do not bypass `REPLACE_EXISTING=1` safeguards for existing tags/releases.
