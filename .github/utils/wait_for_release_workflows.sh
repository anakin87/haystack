#!/bin/bash
# wait_for_workflows.sh - Wait for tag-triggered workflows to complete
#
# Usage: ./wait_for_workflows.sh <tag> <workflow_name1> [workflow_name2] ...
# Requires: GH_TOKEN and GITHUB_REPOSITORY environment variables
#
# Example:
#   ./wait_for_workflows.sh v2.19.0 "Project release on PyPi" "Docker image release"

set -euo pipefail

TAG="$1"
shift
WORKFLOWS=("$@")

MAX_ATTEMPTS=40
SLEEP_SECONDS=30

# Get tag SHA
TAG_SHA=$(gh api "repos/${GITHUB_REPOSITORY}/git/refs/tags/${TAG}" --jq '.object.sha') || {
    echo "❌ Tag ${TAG} not found"
    exit 1
}
echo "Tag ${TAG} (SHA: ${TAG_SHA:0:7})"
echo ""

wait_for_workflow() {
    local name="$1"
    echo "⏳ Waiting for: $name"

    for ((i=1; i<=MAX_ATTEMPTS; i++)); do
        result=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs" \
            --jq ".workflow_runs[] | select(.head_sha == \"${TAG_SHA}\" and .name == \"${name}\")" 2>/dev/null || echo "")

        if [[ -z "$result" ]]; then
            echo "   Attempt $i/$MAX_ATTEMPTS: not started yet..."
            sleep $SLEEP_SECONDS
            continue
        fi

        status=$(echo "$result" | jq -r '.status')
        conclusion=$(echo "$result" | jq -r '.conclusion')

        if [[ "$status" == "completed" ]]; then
            if [[ "$conclusion" == "success" ]]; then
                echo "✅ $name completed"
                return 0
            else
                echo "❌ $name failed: $conclusion"
                return 1
            fi
        fi

        echo "   Attempt $i/$MAX_ATTEMPTS: $status..."
        sleep $SLEEP_SECONDS
    done

    echo "❌ $name: timeout after $((MAX_ATTEMPTS * SLEEP_SECONDS / 60)) minutes"
    return 1
}

for workflow in "${WORKFLOWS[@]}"; do
    wait_for_workflow "$workflow" || exit 1
done

echo ""
echo "✅ All release workflows completed"
