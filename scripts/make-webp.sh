#!/bin/bash
# Makes the website's lighter WebP copies of the screenshots in docs/assets. Needs cwebp (brew install webp).
set -euo pipefail
cd "$(dirname "$0")/../docs/assets"
for f in menu-*.png welcome-*.png window-*.png section-*.png; do
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  [ "$w" -gt 1800 ] && w=1800
  cwebp -quiet -q 84 -alpha_q 90 -resize "$w" 0 "$f" -o "${f%.png}.webp"
done
