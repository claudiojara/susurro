#!/bin/sh
# Renders App/Resources/Icon/AppIcon.svg into every size of the AppIcon set of the asset catalog. The PNGs are
# committed, so a build needs none of this; run it (`make icon`) only after editing the SVG.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SVG="$ROOT/App/Resources/Icon/AppIcon.svg"
SET="$ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/scripts/render-svg.swift" "$SVG" "$WORK/master.png" 1024

mkdir -p "$SET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$WORK/master.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$WORK/master.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
echo "Rendered $SET"
