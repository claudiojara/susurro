#!/usr/bin/env bash
# Starts CI for a branch when the commit at its head has no CI result.
#
# A push made with the workflow token starts no workflow, and GitHub creates the pull_request run for such a commit
# as `action_required`, which gives no result. So the head counts as covered only when a CI run of it passed, failed,
# or is still going. Anything else (no run, a run waiting for approval, a skipped or cancelled run) gets a dispatch.
#
# Reads REPO, BRANCH, SHA (the commit at the head of BRANCH), and GH_TOKEN from the environment.
set -euo pipefail

: "${REPO:?REPO is required}" "${BRANCH:?BRANCH is required}" "${SHA:?SHA is required}"

runs=$(gh run list --repo "$REPO" --workflow ci.yml --commit "$SHA" --limit 50 --json status,conclusion)
covered=$(jq '[.[] | select(.status != "completed" or (.conclusion | IN("success", "failure", "timed_out")))] | length' <<<"$runs")

if ((covered > 0)); then
  echo "CI already has a result, or is running, for ${SHA}; not starting another run."
  exit 0
fi

gh workflow run ci.yml --repo "$REPO" --ref "$BRANCH"
echo "Started CI for ${BRANCH} (${SHA})."
