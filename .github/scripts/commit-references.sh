#!/usr/bin/env bash
# Unpacks the references archive made by the record job and commits them as the Actions bot.
#
# The archive comes from the job that ran the pull request's code, so it is checked before anything is unpacked: every
# entry must be a regular file named like a snapshot picture or the environment record, inside a __Snapshots__ folder
# of a package's Tests folder. Anything else refuses the whole archive. Run it from the checkout.
#
# Usage: commit-references.sh <archive.tar>
# Writes `committed=true` or `committed=false` to $GITHUB_OUTPUT.
set -euo pipefail

archive="${1:?Usage: commit-references.sh <archive.tar>}"
component='[A-Za-z0-9._-]+'
allowed="^Packages/${component}/Tests/(${component}/)+__Snapshots__/((${component}/)?[A-Za-z0-9._+-]+\\.png|environment\\.txt)\$"

unexpected() {
  echo "::error::Unexpected entry in the references archive: $1" >&2
  echo "Unexpected entry in the references archive: $1. Nothing was unpacked." >&2
  exit 1
}

names=$(tar -tf "$archive")
types=$(tar -tvf "$archive" | cut -c1)
if [[ -z "$names" ]]; then
  unexpected "the archive is empty"
fi
while IFS= read -r type; do
  [[ "$type" == "-" ]] || unexpected "an entry that is not a regular file"
done <<<"$types"
while IFS= read -r name; do
  case "/$name/" in
    */../* | */./* | *//*) unexpected "$name" ;;
  esac
  [[ "$name" =~ $allowed ]] || unexpected "$name"
done <<<"$names"

tar -xf "$archive" --no-same-owner

# Only the files that were in the archive, which were all checked above.
files=()
while IFS= read -r name; do
  files+=("$name")
done <<<"$names"
git add -A -- "${files[@]}"
if git diff --cached --quiet; then
  echo "The references are up to date."
  echo "committed=false" >>"${GITHUB_OUTPUT:-/dev/stdout}"
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "test(ui): record snapshot references"
echo "Committed the references."
echo "committed=true" >>"${GITHUB_OUTPUT:-/dev/stdout}"
