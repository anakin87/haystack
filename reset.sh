#!/bin/bash

# Reset script for cleaning up v2.20.x release artifacts
# This script is fail-proof and reports all actions taken

set -u  # Only fail on undefined variables, not on command errors

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Target commit to reset main to
TARGET_COMMIT="76c0268da357a650f43b26ea06c8287ba6576aca"

# Function to print action report
report_action() {
    local status=$1
    local message=$2
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "skipped" ]; then
        echo -e "${YELLOW}⊘${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Function to safely execute a command and report
safe_execute() {
    local description=$1
    shift
    local cmd=("$@")
    
    if "${cmd[@]}" 2>/dev/null; then
        report_action "success" "$description"
        return 0
    else
        report_action "skipped" "$description (not found or already done)"
        return 0
    fi
}

echo "=========================================="
echo "Starting reset operations..."
echo "=========================================="
echo ""

# Step 1: Checkout main and reset to target commit
echo "Step 1: Resetting main branch to commit $TARGET_COMMIT"
if git rev-parse --verify "$TARGET_COMMIT" >/dev/null 2>&1; then
    git checkout main 2>/dev/null || true
    if git reset --hard "$TARGET_COMMIT" 2>/dev/null; then
        report_action "success" "Reset main to commit $TARGET_COMMIT"
    else
        report_action "skipped" "Failed to reset main (may not be on main branch)"
    fi
    
    # Force push main
    if git push origin main --force 2>/dev/null; then
        report_action "success" "Force pushed main to origin"
    else
        report_action "skipped" "Force push main (may need manual intervention or permissions)"
    fi
else
    report_action "skipped" "Target commit $TARGET_COMMIT not found locally"
    echo "  → Fetching from origin..."
    git fetch origin 2>/dev/null || true
    if git rev-parse --verify "$TARGET_COMMIT" >/dev/null 2>&1; then
        git checkout main 2>/dev/null || true
        if git reset --hard "$TARGET_COMMIT" 2>/dev/null; then
            report_action "success" "Reset main to commit $TARGET_COMMIT (after fetch)"
        else
            report_action "skipped" "Failed to reset main (may not be on main branch)"
        fi
        if git push origin main --force 2>/dev/null; then
            report_action "success" "Force pushed main to origin"
        else
            report_action "skipped" "Force push main (may need manual intervention or permissions)"
        fi
    else
        report_action "skipped" "Target commit $TARGET_COMMIT not found even after fetch"
    fi
fi
echo ""

# Step 2: Delete v2.20.x branch (local and remote)
echo "Step 2: Deleting v2.20.x branch"
safe_execute "Deleted local branch v2.20.x" git branch -D v2.20.x
safe_execute "Deleted remote branch v2.20.x" git push origin --delete v2.20.x
echo ""

# Step 3: Delete create-unstable-docs-2.20 branch (local and remote)
echo "Step 3: Deleting create-unstable-docs-2.20 branch"
safe_execute "Deleted local branch create-unstable-docs-2.20" git branch -D create-unstable-docs-2.20
safe_execute "Deleted remote branch create-unstable-docs-2.20" git push origin --delete create-unstable-docs-2.20
echo ""

# Step 4: Delete bump-version branch (local and remote)
echo "Step 4: Deleting bump-version branch"
safe_execute "Deleted local branch bump-version" git branch -D bump-version
safe_execute "Deleted remote branch bump-version" git push origin --delete bump-version
echo ""

# Step 5: Delete GitHub releases for v2.20.0
echo "Step 5: Deleting GitHub releases for v2.20.0"
if command -v gh >/dev/null 2>&1; then
    # Get all releases matching v2.20.0 pattern
    releases=$(gh release list --limit 100 2>/dev/null | grep -E "v2\.20\.0" | awk '{print $1}' 2>/dev/null || true)
    if [ -n "$releases" ]; then
        while IFS= read -r release; do
            [ -z "$release" ] && continue
            safe_execute "Deleted GitHub release: $release" gh release delete "$release" --yes
        done <<< "$releases"
    else
        report_action "skipped" "No v2.20.0 releases found"
    fi
else
    report_action "skipped" "GitHub CLI (gh) not found - cannot delete releases"
    echo "  → Install GitHub CLI to delete releases automatically"
    echo "  → Or delete manually via: gh release delete <release-name> --yes"
fi
echo ""

# Step 6: Delete tags
echo "Step 6: Deleting tags"

# Fetch tags from remote to ensure we have all tags
echo "  → Fetching tags from remote..."
git fetch origin --tags 2>/dev/null || true

# Delete v2.20.0 tag
safe_execute "Deleted local tag v2.20.0" git tag -d v2.20.0
safe_execute "Deleted remote tag v2.20.0" git push origin --delete v2.20.0

# Delete v2.20.0-rc* tags (except v2.20.0-rc0)
echo "  → Deleting v2.20.0-rc* tags (except v2.20.0-rc0)..."
# Get tags from both local and remote, then deduplicate
local_tags=$(git tag -l "v2.20.0-rc*" 2>/dev/null | grep -v "^v2.20.0-rc0$" 2>/dev/null || true)
remote_tags=$(git ls-remote --tags origin 2>/dev/null | grep -E "refs/tags/v2\.20\.0-rc" | sed 's|.*refs/tags/||' | grep -v "^v2.20.0-rc0$" 2>/dev/null || true)
# Combine and deduplicate tags
tags=$(echo -e "${local_tags}\n${remote_tags}" | sort -u)
if [ -n "$tags" ]; then
    while IFS= read -r tag; do
        [ -z "$tag" ] && continue
        safe_execute "Deleted local tag: $tag" git tag -d "$tag"
        safe_execute "Deleted remote tag: $tag" git push origin --delete "$tag"
    done <<< "$tags"
else
    report_action "skipped" "No v2.20.0-rc* tags found (excluding v2.20.0-rc0)"
fi

# Delete v2.21.0-rc0 tag
safe_execute "Deleted local tag v2.21.0-rc0" git tag -d v2.21.0-rc0
safe_execute "Deleted remote tag v2.21.0-rc0" git push origin --delete v2.21.0-rc0

echo ""

# Final summary
echo "=========================================="
echo "Reset operations completed!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Main branch reset to: $TARGET_COMMIT"
echo "  - Branches deleted: v2.20.x, create-unstable-docs-2.20, bump-version"
echo "  - Tags deleted: v2.20.0, v2.20.0-rc* (except v2.20.0-rc0), v2.21.0-rc0"
echo "  - Releases deleted: all v2.20.0 releases"
echo ""
echo "Note: If any operations were skipped, they may not have existed or"
echo "      may require manual intervention (e.g., GitHub CLI for releases)."

