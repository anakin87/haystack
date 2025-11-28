#!/bin/bash
# release_version.sh - Parse and validate version for release
#
# Usage: ./release_version.sh <version>
# Output: Writes to $GITHUB_OUTPUT if set, otherwise to stdout
#
# Examples:
#   ./release_version.sh v2.99.0-rc1   # First RC of minor
#   ./release_version.sh v2.99.0-rc2   # Subsequent RC
#   ./release_version.sh v2.99.0       # Final release

set -euo pipefail

# --- Helpers ---

fail() {
    echo "❌ $1"
    exit 1
}

ok() {
    echo "✅ $1"
}

tag_exists() {
    git tag -l "$1" | grep -q "^$1$"
}

branch_exists() {
    git ls-remote --heads origin "$1" | grep -q "$1"
}

# --- Parse version ---

VERSION="${1#v}"  # Strip 'v' prefix

if [[ ! "${VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-rc([0-9]+))?$ ]]; then
    fail "Invalid version: $1. Expected: vMAJOR.MINOR.PATCH[-rcN]"
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"
RC_NUM="${BASH_REMATCH[5]:-0}"

# rc0 is an internal marker, not a valid release
if [[ "${RC_NUM}" == "0" && "${VERSION}" == *"-rc0" ]]; then
    fail "Cannot release rc0. It is created automatically during branch-off."
fi

MAJOR_MINOR="${MAJOR}.${MINOR}"
RELEASE_BRANCH="v${MAJOR_MINOR}.x"
TAG="v${VERSION}"

IS_FIRST_RC="false"
if [[ "${PATCH}" == "0" && "${RC_NUM}" == "1" ]]; then
    IS_FIRST_RC="true"
fi

echo "ℹ️  Validating: ${VERSION} (branch: ${RELEASE_BRANCH}, first_rc: ${IS_FIRST_RC})"

# --- Validations ---

# 1. Tag must not already exist
if tag_exists "${TAG}"; then
    fail "Tag ${TAG} already exists"
fi
ok "Tag ${TAG} does not exist"

# 2. Checks based on release type
if [[ "${IS_FIRST_RC}" == "true" ]]; then
    # First RC: branch must NOT exist yet
    if branch_exists "${RELEASE_BRANCH}"; then
        fail "Branch ${RELEASE_BRANCH} already exists (should not for first RC)"
    fi
    ok "Branch ${RELEASE_BRANCH} does not exist"

    # First RC: VERSION.txt must contain rc0
    EXPECTED="${MAJOR_MINOR}.0-rc0"
    ACTUAL=$(cat VERSION.txt)
    if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
        fail "VERSION.txt: expected ${EXPECTED}, found ${ACTUAL}"
    fi
    ok "VERSION.txt = ${EXPECTED}"

else
    # Not first RC: branch must exist
    if ! branch_exists "${RELEASE_BRANCH}"; then
        fail "Branch ${RELEASE_BRANCH} does not exist"
    fi
    ok "Branch ${RELEASE_BRANCH} exists"

    # Subsequent RC (rc2, rc3...): previous RC must exist
    if [[ "${RC_NUM}" -gt 1 ]]; then
        PREV_TAG="v${MAJOR_MINOR}.${PATCH}-rc$((RC_NUM - 1))"
        if ! tag_exists "${PREV_TAG}"; then
            fail "Previous tag ${PREV_TAG} does not exist"
        fi
        ok "Previous tag ${PREV_TAG} exists"
    fi

    # Final release: at least one RC must exist, and tests must have passed
    if [[ "${RC_NUM}" == "0" ]]; then
        RC_TAGS=$(git tag -l "v${MAJOR_MINOR}.${PATCH}-rc*" | grep -v "\-rc0$" || true)
        if [[ -z "${RC_TAGS}" ]]; then
            fail "No RC tags found for ${MAJOR_MINOR}.${PATCH}"
        fi
        LAST_RC=$(echo "${RC_TAGS}" | sort -V | tail -n1)
        ok "Found RC: ${LAST_RC}"

        # Check Tests workflow passed (only if credentials available)
        if [[ -n "${GH_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
            RC_SHA=$(git rev-list -n 1 "${LAST_RC}")
            RESULT=$(gh api "/repos/${GITHUB_REPOSITORY}/actions/runs?head_sha=${RC_SHA}&status=success" \
                --jq '.workflow_runs[] | select(.name == "Tests") | .conclusion' 2>/dev/null || true)
            if [[ -z "${RESULT}" ]]; then
                fail "Tests did not pass on ${LAST_RC}"
            fi
            ok "Tests passed on ${LAST_RC}"
        fi
    fi
fi

ok "All validations passed!"

# --- Output to GITHUB_OUTPUT (or stdout for local testing) ---

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

{
    echo "version=${VERSION}"
    echo "major_minor=${MAJOR_MINOR}"
    echo "release_branch=${RELEASE_BRANCH}"
    echo "is_first_rc=${IS_FIRST_RC}"
} >> "${OUTPUT_FILE}"
