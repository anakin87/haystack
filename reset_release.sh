#!/usr/bin/env bash
#
# reset_release.sh — wipe the Haystack 3.0 *dry-run* artifacts from the fork so a release
# rehearsal can be re-run cleanly.
#
#   ./reset_release.sh          # show what would be deleted, then ask
#   ./reset_release.sh -y       # delete without confirmation
#
# Scope & safety:
#   - Operates ONLY on anakin87/haystack (refuses to run if origin is anything else).
#   - NEVER touches deepset-ai and NEVER deletes v3.0.0-rc0 (the upstream-aligned tag).
#   - Deletes only release-run artifacts; commits/pushes no source code of its own.
#
# What it removes for the v3.0.x line:
#   tags     : v3.0.0, v3.0.0-rc1.. (NOT rc0), v3.1.0-rc0   (remote + local)
#   branches : v3.0.x, bump-version, promote-unstable-docs-*  (remote)
#   PRs      : open PRs from bump-version / promote-unstable-docs-*
#   releases : GitHub releases for v3.0.0 and v3.0.0-rc*
#   runs     : cancels in-progress workflow runs
#   main     : strips commits a *merged* bump/promote PR left on main (VERSION.txt bump +
#              generated unstable docs), restoring main to the last non-rehearsal commit.
#              Done via force-with-lease; local main is reset only if the working tree is clean.

set -uo pipefail

REPO="anakin87/haystack"
ASSUME_YES="${1:-}"

# Subjects of commits a rehearsal merges into main (bump PR + promote PR, squash or merge-commit).
REHEARSAL_RE='Bump unstable version and create unstable docs|Promote unstable docs for Haystack|Merge pull request #[0-9]+ from anakin87/(bump-version|promote-unstable-docs)'

# --- safety guard: origin must be the fork ---------------------------------
origin_url="$(git remote get-url origin 2>/dev/null || true)"
case "$origin_url" in
  *anakin87/haystack*) : ;;
  *) echo "REFUSING: origin is '$origin_url', not anakin87/haystack." >&2; exit 1 ;;
esac

keep_tag() { [ "$1" = "v3.0.0-rc0" ]; }   # upstream-aligned tag we must preserve

# --- discover artifacts ----------------------------------------------------
del_tags=()
while IFS= read -r t; do
  [ -z "$t" ] && continue
  keep_tag "$t" && continue
  case "$t" in
    v3.0.0|v3.0.0-rc*|v3.1.0-rc0) del_tags+=("$t") ;;
  esac
done < <(git ls-remote --tags origin 2>/dev/null | sed 's#.*refs/tags/##' | grep -v '\^{}$')

del_branches=()
while IFS= read -r b; do
  [ -z "$b" ] && continue
  case "$b" in
    v3.0.x|bump-version|promote-unstable-docs-*) del_branches+=("$b") ;;
  esac
done < <(git ls-remote --heads origin 2>/dev/null | sed 's#.*refs/heads/##')

del_prs=()
while IFS= read -r n; do
  [ -z "$n" ] && continue
  del_prs+=("$n")
done < <(gh pr list -R "$REPO" --state open --json number,headRefName \
           --jq '.[] | select(.headRefName=="bump-version" or (.headRefName|startswith("promote-unstable-docs-"))) | .number' 2>/dev/null)

del_releases=()
while IFS= read -r r; do
  [ -z "$r" ] && continue
  case "$r" in
    v3.0.0|v3.0.0-rc*) keep_tag "$r" && continue; del_releases+=("$r") ;;
  esac
done < <(gh release list -R "$REPO" --json tagName --jq '.[].tagName' 2>/dev/null)

# --- discover rehearsal commits merged into main ---------------------------
git fetch -q origin main 2>/dev/null || true
main_tip="$(git rev-parse origin/main 2>/dev/null || echo '')"
baseline=""
if [ -n "$main_tip" ]; then
  # Walk main first-parent from the tip; skip contiguous rehearsal commits; stop at the first
  # real commit — that becomes the baseline main is reset to.
  while IFS=$'\t' read -r sha subj; do
    if printf '%s' "$subj" | grep -Eq "$REHEARSAL_RE"; then
      continue
    fi
    baseline="$sha"; break
  done < <(git log --first-parent --format='%H%x09%s' origin/main 2>/dev/null)
fi
strip_main=false
if [ -n "$baseline" ] && [ "$baseline" != "$main_tip" ]; then
  strip_main=true
fi

# --- plan ------------------------------------------------------------------
echo "Reset plan for $REPO (v3.0.0-rc0 is always preserved):"
echo "  tags     : ${del_tags[*]:-(none)}"
echo "  branches : ${del_branches[*]:-(none)}"
echo "  PRs      : ${del_prs[*]:-(none)}"
echo "  releases : ${del_releases[*]:-(none)}"
echo "  + cancel any in-progress workflow runs"
if $strip_main; then
  echo "  main     : FORCE-PUSH main -> ${baseline:0:9} (strips merged rehearsal commits):"
  git --no-pager log --oneline "${baseline}..${main_tip}" | sed 's/^/               - /'
else
  echo "  main     : (clean — no merged rehearsal commits to strip)"
fi
echo

if [ "$ASSUME_YES" != "-y" ]; then
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y) : ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- execute ---------------------------------------------------------------
for n in "${del_prs[@]:-}";      do [ -n "$n" ] && { echo "close PR #$n";        gh pr close "$n" -R "$REPO" --delete-branch 2>/dev/null || true; }; done
for r in "${del_releases[@]:-}"; do [ -n "$r" ] && { echo "delete release $r";   gh release delete "$r" -R "$REPO" --yes 2>/dev/null || true; }; done
for b in "${del_branches[@]:-}"; do [ -n "$b" ] && { echo "delete branch $b";    git push origin --delete "$b" 2>/dev/null || true; }; done
for t in "${del_tags[@]:-}";     do [ -n "$t" ] && { echo "delete tag $t";       git push origin --delete "$t" 2>/dev/null || true; git tag -d "$t" 2>/dev/null || true; }; done

while IFS= read -r rid; do
  [ -z "$rid" ] && continue
  echo "cancel run $rid"
  gh run cancel "$rid" -R "$REPO" 2>/dev/null || true
done < <(gh run list -R "$REPO" --status in_progress --json databaseId --jq '.[].databaseId' 2>/dev/null)

# --- strip merged rehearsal commits from main ------------------------------
if $strip_main; then
  echo "strip main -> ${baseline:0:9} (force-with-lease)"
  if git push --force-with-lease="main:${main_tip}" origin "${baseline}:main"; then
    # Reset local main too, but ONLY if the working tree has no uncommitted tracked changes,
    # so we never destroy work in progress.
    cur="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$cur" = "main" ] && [ -z "$(git status --porcelain --untracked-files=no)" ]; then
      git reset --hard "$baseline"
      echo "local main reset to ${baseline:0:9}"
    else
      echo "NOTE: local main NOT reset (not on a clean 'main')."
      echo "      When ready:  git checkout main && git reset --hard $baseline"
    fi
  else
    echo "WARN: main force-push skipped (remote moved, or lease failed). Re-run to retry."
  fi
fi

echo
echo "Done. Verify with:"
echo "  git ls-remote --tags origin 'v3*'   # expect only v3.0.0-rc0"
echo "  gh pr list -R $REPO"
echo "  git show origin/main:VERSION.txt     # expect the pre-bump value, not 3.1.0-rc0"
