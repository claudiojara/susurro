#!/usr/bin/env bash
# Pushes the references commit to the branch, then makes sure CI runs for the head.
#
# This is the only step of the record-snapshots workflow that holds a token that can write. It runs in a clean checkout,
# in a job that has run none of the pull request's code.
#
# Reads REPO, BRANCH, SHA (the commit the branch had when the references were recorded), and GH_TOKEN from the
# environment. REMOTE_URL replaces the GitHub address, for tests. Run it from the checkout.
set -euo pipefail

: "${REPO:?REPO is required}" "${BRANCH:?BRANCH is required}" "${SHA:?SHA is required}" "${GH_TOKEN:?GH_TOKEN is required}"
remote="${REMOTE_URL:-https://github.com/${REPO}.git}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

head=$(git rev-parse HEAD)
if [[ "$head" != "$SHA" ]]; then
  # Authenticate for this one command, as actions/checkout does, and keep the header out of the log.
  header="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
  echo "::add-mask::${header}"
  if ! git -c "http.https://github.com/.extraheader=${header}" push "$remote" "HEAD:refs/heads/${BRANCH}"; then
    msg="The branch '${BRANCH}' moved while the references were recorded, or the push was refused. Nothing was overwritten. Run the workflow again."
    echo "::error::${msg}" >&2
    echo "$msg" >&2
    exit 1
  fi
  echo "Pushed the references to ${BRANCH}."
else
  echo "Nothing to push: ${BRANCH} already has the references."
fi

SHA="$head" "${script_dir}/dispatch-ci.sh"
