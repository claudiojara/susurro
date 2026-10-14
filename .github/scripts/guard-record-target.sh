#!/usr/bin/env bash
# Decides whether the record-snapshots workflow may record on a branch, and finds the commit to record on.
#
# The workflow commits to the branch it records on, so it must never be pointed at the default branch or at a branch
# nobody is reviewing. It records only on the branch of an open pull request whose head is in this repository.
#
# Reads REPO (owner/name), BRANCH, DEFAULT_BRANCH, and GH_TOKEN (read access to pull requests) from the environment,
# and writes `branch=` and `sha=` to $GITHUB_OUTPUT.
set -euo pipefail

: "${REPO:?REPO is required}" "${BRANCH:?BRANCH is required}" "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"

refuse() {
  echo "::error::$1" >&2
  echo "$1" >&2
  exit 1
}

if [[ "$BRANCH" == "$DEFAULT_BRANCH" ]]; then
  refuse "Refusing to record on the default branch ($DEFAULT_BRANCH): the workflow commits to the branch it records on. Start it on the branch of a pull request."
fi
if [[ "$BRANCH" =~ [[:cntrl:]] ]]; then
  refuse "Refusing a branch name with control characters."
fi

owner="${REPO%%/*}"
pulls=$(gh api --method GET "repos/${REPO}/pulls" -f state=open -f head="${owner}:${BRANCH}" -f per_page=100)
sha=$(jq -r --arg repo "$REPO" --arg branch "$BRANCH" \
  '[.[] | select(.head.repo.full_name == $repo and .head.ref == $branch)] | first | .head.sha // empty' <<<"$pulls")

if [[ -z "$sha" ]]; then
  refuse "No open pull request from the branch '${BRANCH}' of ${REPO}. The workflow records only on the branch of an open pull request from this repository, never on a fork or a branch nobody reviews."
fi
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  refuse "GitHub answered with something that is not a commit id: '${sha}'."
fi

{
  echo "branch=${BRANCH}"
  echo "sha=${sha}"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"
echo "Recording on ${BRANCH} at ${sha}."
