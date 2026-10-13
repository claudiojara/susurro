#!/usr/bin/env bash
# Packs the snapshot references of the packages' own tests into a tar archive for commit-references.sh.
#
# Only the Tests folders of the packages are read. A search below Packages would also find the references of the
# dependencies that SwiftPM checks out in .build, which are not ours to commit. Run it from the repository root.
#
# Usage: pack-references.sh <archive.tar>
set -euo pipefail

archive="${1:?Usage: pack-references.sh <archive.tar>}"
list="$(mktemp)"
trap 'rm -f "$list"' EXIT

find Packages/*/Tests -path '*/__Snapshots__/*' -type f \( -name '*.png' -o -name environment.txt \) | sort >"$list"
if [[ ! -s "$list" ]]; then
  echo "No snapshot references were found in the Tests folders of the packages." >&2
  exit 1
fi
tar -cf "$archive" -T "$list"
echo "Packed $(wc -l <"$list" | tr -d ' ') files."
