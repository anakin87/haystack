# Haystack 3.0 release dry-run: fork handoff

This fork (`anakin87/haystack`) is used to **rehearse the Haystack 3.0 release** end to end,
with **no real artifacts published**. The point is to prove the release **orchestration and
tag-triggering** work for a `3.0.0` version (everything was designed for `2.x`), before running
the real thing on `deepset-ai/haystack`.

## Current state of this fork

**Everything is committed and pushed** — local `main` == `origin/main`. The dry-run is ready to run.

- The 5 dry-run workflow files are committed in **`4885f39b6` ("adapt workflows for fork and dry
  run")**: `branch_off.yml`, `docker_release.yml`, `promote_unstable_docs.yml`, `pypi_release.yml`,
  `release.yml`.
- The Layer-1 fixes (below) are committed in earlier commits.
- Fork **Actions are enabled** (`allow all actions`).
- The **`RELEASE_PAT`** Actions secret exists (classic PAT, `repo` + `workflow`).
- Fork **tags are aligned** with upstream through `v3.0.0-rc0` (see "Tag alignment" below).

Only `summary.md` (this file) is untracked.

### Layer 1: the real 3.0 fixes (these mirror what will go into `deepset-ai/haystack:main`)

These make the release process actually work for a major bump. Committed on the fork:

- `.github/workflows/github_release.yml`: tag filter `v2.` generalized to `v[0-9]+.` (else a
  `v3.0.0-rc1` tag would not trigger the GitHub release).
- `.github/workflows/docker_release.yml`: tag filter generalized the same way; stable-detect regex
  `^v2\.` generalized to `^v[0-9]+\.`.
- `.github/utils/promote_unstable_docs_docusaurus.py`: `previous_stable` is read from the config's
  current `lastVersion` instead of `minor - 1` (which produced `3.-1` at the 2->3 boundary).
- `docs-website/docusaurus.config.js`: unstable label `2.32-unstable` corrected to `3.0-unstable`
  (two places).

### Layer 2: dry-run neutering (fork-only, do NOT port to the real repo)

Makes the run produce no external side effects:

- `pypi_release.yml`: keeps `hatch build` (packaging is still exercised); the PyPI publish is
  replaced with a print of `dist/`. Removed `environment: pypi` and `id-token`.
- `docker_release.yml`: owner guard flipped `deepset-ai` -> `anakin87` so the job still RUNS on the
  fork (this is what proves the tag triggers it); the QEMU/buildx/login + multi-arch build/push/test
  are replaced with a print.
- `release.yml`:
  - `authorize` job uses `github.token` (default token is fine for the read-only role check).
  - `create-release-tag` uses `secrets.RELEASE_PAT` for the tag push (see "Why a PAT" below).
  - `check-artifacts`: the PyPI and Docker curl checks are faked with prints; the GitHub-release
    check stays real (a real release IS created on the fork).
  - the 3 platform bump jobs (`bump-dc-pipeline-templates`, `bump-deepset-cloud-custom-nodes`,
    `bump-haystack-runtime`) are set to `if: false` (they target private deepset-ai repos).
  - the Slack post is replaced with a print of the payload.
- `branch_off.yml`: branch/tag pushes + PR use `secrets.RELEASE_PAT`. The `reviewers:
  ${{ github.actor }}` request was removed: the PR author is the `RELEASE_PAT` owner (`anakin87` =
  `github.actor`), and GitHub rejects requesting a review from a PR's own author (this broke the
  first attempt at PR #158). `push_release_notes_to_website.yml` still carries the same line but is
  `workflow_dispatch`-only, so it never fires in the release path.
- `promote_unstable_docs.yml`: the promote-docs PR uses `secrets.RELEASE_PAT` (only fires on the
  final `v3.0.0` run, not on RCs).
- `github_release.yml`: the "Add contributor list" step is skipped (print only). The real step does
  `gh api repos/deepset-ai/haystack/compare/<rc0>...<rc1>`, which **404s on the fork** because the
  RC tags exist only here — it was failing the GitHub-release job. The release body
  (`enhanced_relnotes.md`) is still generated; it just omits the thank-you section.
- `.github/utils/parse_validate_version.sh`: the final-release **Tests-passed gate** is skipped
  (print only). It normally blocks a stable `vX.Y.0` release until the "Tests" workflow succeeded on
  the last RC commit; waiting for that on the fork is slow and not what this rehearsal verifies.

## Verified: no real-world release risk

Confirmed against the pushed code — running the release cannot publish or write to any real
(`deepset-ai` / PyPI / Docker Hub / Slack) target:

- **Only credential on the fork is `RELEASE_PAT`.** Absent: `HAYSTACK_BOT_TOKEN`,
  `DOCKER_HUB_USER/TOKEN`, `SLACK_WEBHOOK_URL_NOTIFICATIONS`, PyPI OIDC trust. So even a missed
  neutering step has no credential to reach the outside world.
- **Every writable artifact targets the running repo (the fork), with no override.** Tags, the
  `v3.0.x` release branch, version-bump commits, the GitHub release (`ncipollo/release-action`, no
  `repo:`), and both PRs (`peter-evans/create-pull-request`, no `repository:`/`push-to-fork:`,
  `base: main`) all resolve to `anakin87/haystack`. `create-release-tag` pushes to `origin`, which
  in a checked-out workflow is the repo running it.
- **The only literal `deepset-ai/...` references are inert:** the 3 platform-bump jobs are
  `if: false`; `github_release.yml` does a read-only `gh api repos/deepset-ai/haystack/compare` for
  the contributor list; `push_release_notes_to_website.yml` is `workflow_dispatch`-only (never fires
  on a release) and needs the absent bot token.
- **CI Slack "notify on failure"** steps (`tests.yml`/`slow.yml`/`e2e.yml`) need the absent webhook
  secret, so they post nothing — just wasted minutes.

`RELEASE_PAT` is a broad token (your account, `repo`+`workflow`) but is only ever used to push to
the fork itself. Consider deleting it after the rehearsal.

## Tag alignment

The fork previously had tags only up to `v2.21.0-rc0` (GitHub forks don't auto-inherit upstream
tags, and there was no `upstream` remote locally). It is now aligned with `deepset-ai/haystack`
through `v3.0.0-rc0`, done **without triggering any workflow**: Actions were disabled on the fork,
tags fetched from upstream and pushed to `origin`, then Actions re-enabled (GitHub does not
retroactively fire events for pushes made while Actions were off).

- A local `upstream` remote (`deepset-ai/haystack`) was added for this.
- `v3.0.0-rc0` now exists on the fork. It does **not** collide with the planned `v3.0.0-rc1` /
  `v3.0.0` dry-run tags.
- Note: `git fetch upstream --tags` silently no-ops under the sandbox; use
  `git fetch upstream '+refs/tags/*:refs/tags/*'` (sandbox disabled) if re-syncing.

## How to run

```bash
# from the fork, first RC (covers branch-off + first-RC path + all tag triggers)
gh workflow run release.yml -R anakin87/haystack -f version=v3.0.0-rc1

# then the final release (covers the "tests passed on last RC" gate + docs promote PR)
gh workflow run release.yml -R anakin87/haystack -f version=v3.0.0
```

Default dispatch runs `release.yml` from the fork's default branch (`main`), which is correct here.

## What to verify after the RC run

- The `v3.0.0-rc1` tag exists and **triggered** all three: "Project release on PyPi",
  "Project release on Github", "Docker image release" (they should run and show the DRY RUN prints).
- The `v3.0.x` release branch was created.
- A "Bump unstable version and create unstable docs" PR was opened on the fork, bumping VERSION.txt
  to `3.1.0-rc0` and adding `3.0-unstable` docs.
- A real GitHub release for `v3.0.0-rc1` exists on the fork (reno + pandoc path worked).
- The 3 platform bump jobs show as **skipped**; the Slack step printed a payload instead of posting.

For the final `v3.0.0` run, additionally expect a "promote unstable docs" PR flipping
`lastVersion` to `3.0`.

## Known open item

- None currently. The final-release "Tests passed on last RC" gate in
  `parse_validate_version.sh` — previously the main blocker — is now neutered (see Layer 2).

## Re-running from scratch

No rulesets on the fork, so you can delete and redo freely. Use the helper script (untracked, at
the repo root) — it removes the dry-run artifacts (tags, branches, PRs, GitHub releases), cancels
in-progress runs, and **strips commits a merged bump/promote PR left on `main`** (restoring
`VERSION.txt`, via force-with-lease; local `main` is reset only when the working tree is clean). It
**always preserves the upstream-aligned `v3.0.0-rc0`** and refuses to run if `origin` isn't the
fork:

```bash
./reset_release.sh        # shows a plan, then asks to confirm
./reset_release.sh -y     # skip the confirmation
```

Equivalent manual steps, if you prefer:

```bash
git push origin --delete v3.0.x v3.0.0-rc1 v3.1.0-rc0 2>/dev/null || true
git tag -d v3.0.0-rc1 v3.1.0-rc0 2>/dev/null || true
# also close/delete the bump-version PR and branch if created
```

Heavy CI (`tests.yml`, `slow.yml`, `e2e.yml`) will also trigger on the branch/tag pushes. Expected
and harmless; ignore or disable those workflows on the fork to save minutes.

## Related context (real repo, not this fork)

- A separate task tracks making 2.31.x bugfix releases not interfere with the 3.x line (Docker
  `stable`, platform PRs). Not part of this dry run.
- The full analysis of what breaks for 3.0 lives in `report.md` on `deepset-ai/haystack:main`
  (local `dev/haystack`).
</content>
</invoke>
