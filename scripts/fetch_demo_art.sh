#!/usr/bin/env bash
#
# Rebuilds the demo sleeve set used by review captures.
#
#   scripts/fetch_demo_art.sh [output-dir]     # default: .demo-art
#   DEMO_ART=.demo-art scripts/capture_screens.sh shots ru
#
# ## Why this script exists
#
# Review frames must show real sleeves — a wall of generated gradients tells
# you nothing about whether a layout works. The first version of this fetched
# famous covers from the iTunes Search API, which solved the wrong half of the
# problem and created a worse one:
#
#   * Somebody else's copyrighted artwork was on screen in every frame, on
#     invented tracks. "Field Recordings by Peral" wearing Tame Impala's
#     *Currents* looks broken before it looks illegal, and it is both. Those
#     frames could never have gone near an App Store listing.
#   * The files lived only in a scratch directory. It was cleaned; the dealer
#     cycles modulo the file count; six albums rendered the same sleeve, and a
#     capture set went out claiming "with real covers".
#
# So: public-domain paintings, fetched from Wikimedia Commons and filtered to
# PD only — no attribution required, no licence text to carry, nothing to
# withdraw. They read as credible sleeves because half the record covers ever
# printed are a painting in a square crop. And the set is reproducible, so
# losing the directory costs one command rather than a wrong screenshot.
#
set -euo pipefail

OUT="${1:-.demo-art}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

# Records and shows get separate pools: a podcast wearing a record's sleeve is
# the same category error in miniature.
SLEEVES=(
  "Hilma af Klint Group IX SUW"
  "The Great Wave off Kanagawa"
  "Van Gogh - Starry Night - Google Art Project"
  "Wassily Kandinsky - Composition VIII"
  "Katsushika Hokusai - Fine Wind Clear Morning"
  "Ivan Aivazovsky - The Ninth Wave"
  "Kazimir Malevich - Suprematism"
  "Paul Klee - Castle and Sun"
)
SHOWS=(
  "Caspar David Friedrich - Wanderer above the sea of fog"
  "Turner - The Fighting Temeraire"
  "Edvard Munch - The Scream"
)

mkdir -p "$OUT/podcasts"

# Resolves one title to a thumbnail URL, and only if Commons reports it as
# public domain. Anything else prints nothing and is skipped — a CC BY-SA
# image would oblige the app to carry an attribution it has nowhere to put.
resolve() {
  local title="$1"
  local query
  query=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$title")
  curl -sf -A "$UA" --max-time 25 \
    "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrsearch=$query&gsrnamespace=6&gsrlimit=1&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=800" \
  | python3 -c "
import json, sys
try:
    page = list(json.load(sys.stdin)['query']['pages'].values())[0]
    info = page['imageinfo'][0]
    licence = info.get('extmetadata', {}).get('LicenseShortName', {}).get('value', '')
    print(info['thumburl'] if ('ublic domain' in licence or licence.startswith('PD')) else '')
except Exception:
    print('')
"
}

# A sleeve is square. Crop to the centre rather than squash the painting.
square() {
  local file="$1"
  sips -Z 900 "$file" --out "$file" >/dev/null 2>&1
  local w h side
  w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')
  side=$(( w < h ? w : h ))
  sips -c "$side" "$side" "$file" --out "$file" >/dev/null 2>&1
  sips -Z 600 "$file" --out "$file" >/dev/null 2>&1
}

fetch_into() {
  local dir="$1" prefix="$2"; shift 2
  local index=0
  for title in "$@"; do
    index=$((index + 1))
    local url
    url=$(resolve "$title" || true)
    if [ -z "$url" ]; then
      echo "  skip (not public domain): $title"
      continue
    fi
    local file="$dir/${prefix}${index}.jpg"
    if curl -sf -A "$UA" --max-time 30 "$url" -o "$file"; then
      square "$file"
      echo "  $(basename "$file") — $title"
    else
      echo "  skip (fetch failed): $title"
    fi
    sleep 1   # Commons asks for politeness, and this runs rarely.
  done
}

echo "Sleeves → $OUT"
fetch_into "$OUT" sleeve "${SLEEVES[@]}"
echo "Show art → $OUT/podcasts"
fetch_into "$OUT/podcasts" pod "${SHOWS[@]}"

count=$(ls -1 "$OUT"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
shows=$(ls -1 "$OUT"/podcasts/*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo "Done: $count sleeves, $shows show covers."
[ "$count" -ge 6 ] || echo "WARNING: fewer than six sleeves — records will repeat one."
