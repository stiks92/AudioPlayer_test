#!/usr/bin/env bash
#
# Builds the demo catalogue used by review captures: real releases, real
# sleeves, and a manifest.json that DemoCatalog reads so titles, artists,
# tracklists and covers all belong to each other.
#
#   scripts/fetch_demo_art.sh [output-dir]        # default: .demo-art
#   scripts/fetch_demo_art.sh --paintings [dir]   # old public-domain fallback
#   DEMO_ART=.demo-art scripts/capture_screens.sh shots ru
#
# ## The history, because it is three mistakes deep
#
# v1 fetched famous covers from iTunes and dealt them to invented tracks:
# somebody else's copyrighted art on every frame, and "Field Recordings by
# Peral" wearing Tame Impala's *Currents*. v2 swapped in public-domain
# paintings: legal, but the owner said the covers still looked strange — and
# they did, because a music library wearing Hokusai and Kandinsky reads as a
# museum, not a record shop. Both versions had the same root defect: the art
# and the music were strangers.
#
# v3 stops pretending. The albums are real Creative-Commons releases from the
# Internet Archive's netlabels collection — with their own titles, artists,
# tracklists, durations and covers. The shows are the actual top podcasts of
# the RU directory, which the app can genuinely subscribe to. Nothing on
# screen is invented except the listening statistics, and nothing is borrowed
# from a rights holder who didn't publish it freely. LICENSES.txt records
# each release's licence URL.
#
set -euo pipefail

MODE="real"
if [ "${1:-}" = "--paintings" ]; then MODE="paintings"; shift; fi
OUT="${1:-.demo-art}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

mkdir -p "$OUT/podcasts"

# A sleeve is square. Crop to the centre rather than squash the art.
square() {
  local file="$1"
  sips -Z 900 "$file" --out "$file" >/dev/null 2>&1 || return 0
  local w h side
  w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')
  side=$(( w < h ? w : h ))
  sips -c "$side" "$side" "$file" --out "$file" >/dev/null 2>&1
  sips -Z 600 "$file" --out "$file" >/dev/null 2>&1
}

# ── Real mode: netlabel albums + top podcasts + manifest ─────────────────────
fetch_real() {
  OUT="$OUT" UA="$UA" python3 - <<'PYEOF'
import json, os, re, sys, urllib.parse, urllib.request

OUT = os.environ["OUT"]
HEADERS = {"User-Agent": os.environ["UA"]}

def get_json(url):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def download(url, path):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=45) as r, open(path, "wb") as f:
        f.write(r.read())

def parse_length(value):
    if not value: return None
    s = str(value)
    if ":" in s:
        parts = s.split(":")
        try: return sum(float(p) * 60 ** i for i, p in enumerate(reversed(parts)))
        except ValueError: return None
    try: return float(s)
    except ValueError: return None

def creator_of(meta):
    c = meta.get("creator")
    if isinstance(c, list): c = c[0] if c else None
    if not c or not isinstance(c, str): return None
    # A label is not an artist: "No-Source Netlabel" in the artist slot reads
    # as broken metadata even when it is technically what the item says.
    if re.search(r"various|netlabel|records|recordings|\blabel\b|archive", c, re.I): return None
    return c.strip()

# The most-downloaded netlabel releases: two decades of free electronic
# records whose covers were designed by people who meant them.
query = urllib.parse.quote("collection:(netlabels) AND mediatype:(audio)")
docs = get_json(
    "https://archive.org/advancedsearch.php?q=" + query +
    "&fl[]=identifier&sort[]=downloads+desc&rows=60&page=1&output=json"
)["response"]["docs"]

albums, licences = [], []
for doc in docs:
    if len(albums) >= 8: break
    ident = doc["identifier"]
    try:
        m = get_json(f"https://archive.org/metadata/{ident}")
    except Exception:
        continue
    meta, files = m.get("metadata", {}), m.get("files", [])
    artist = creator_of(meta)
    title = meta.get("title")
    if not artist or not title or not isinstance(title, str): continue
    # Netlabels put shipping labels in titles — catalogue codes, dates of
    # live sets, the artist's own name again. A record shop shelves none of
    # that, so neither does the fixture.
    if re.match(r"^\d{4}-\d{2}-\d{2}", title.strip()): continue   # a taped date, not an album
    title = title.strip()
    title = re.sub(r"\[[A-Za-z]{2,14}[ -]?\d{2,4}\]", "", title)    # [mtk140], [onorezdiLP014]
    title = re.sub(r"\s*\([^)]*\d[^)]*\)\s*$", "", title)           # trailing "(Dec. 15, 2013)"
    title = re.sub(r"^[A-Z]{3,10}\d{2,4}\s+", "", title)             # VKRSNL038 …
    title = re.sub(r"\s*\((LP|EP|Album)\)\s*$", "", title, flags=re.I)
    if title.lower().startswith(artist.lower() + " - "):
        title = title[len(artist) + 3:]
    if title.lower().startswith(artist.lower() + " "):
        title = title[len(artist) + 1:]
    title = re.sub(r"\s{2,}", " ", title).strip(" -–—")
    if not (3 <= len(title) <= 44): continue

    # Tracks must carry real title metadata — filename-derived names are the
    # kind of debris that made earlier fixtures look wrong.
    tracks, seen = [], set()
    for f in files:
        if "MP3" not in f.get("format", ""): continue
        t = f.get("title")
        if not t: continue
        t = re.sub(r"^\d{1,2}[ .\-–]+", "", t.strip())[:60]   # "01 Title" is a rip, not a name
        if not t or t in seen: continue
        seen.add(t)
        tracks.append({"title": t, "duration": parse_length(f.get("length"))})
    if len(tracks) < 3: continue

    # The cover: prefer a file that says it is one, else the largest image.
    def is_art(f):
        name = f.get("name", "").lower()
        if not name.endswith((".jpg", ".jpeg", ".png")): return False
        return not any(bad in name for bad in ("thumb", "spectrogram", "itemimage", "_rules"))
    art = [f for f in files if is_art(f)]
    named = [f for f in art if any(k in f["name"].lower() for k in ("cover", "front", "folder"))]
    pool = named or art
    pool = [f for f in pool if 15_000 <= int(f.get("size", 0) or 0) <= 4_000_000]
    if not pool: continue
    cover = max(pool, key=lambda f: int(f.get("size", 0) or 0))

    index = len(albums) + 1
    file_name = f"sleeve{index}.jpg"
    try:
        download(f"https://archive.org/download/{ident}/{urllib.parse.quote(cover['name'])}",
                 os.path.join(OUT, file_name))
    except Exception:
        continue

    year = None
    for key in ("year", "date"):
        raw = str(meta.get(key, ""))[:4]
        if raw.isdigit(): year = int(raw); break

    albums.append({"file": file_name, "title": title, "artist": artist[:40],
                   "year": year, "tracks": tracks[:3]})
    licences.append(f"{ident} | {meta.get('licenseurl', 'see item page')} | https://archive.org/details/{ident}")
    print(f"  {file_name} — {artist[:30]} · {title[:36]} ({len(tracks[:3])} tracks)")

if len(albums) < 6:
    sys.exit(f"only {len(albums)} usable albums — refusing to write a set that repeats sleeves")

# The actual top of the RU podcast directory — shows the app can subscribe to.
shows = []
try:
    feed = get_json("https://itunes.apple.com/ru/rss/toppodcasts/limit=12/json")["feed"]["entry"]
    for entry in feed:
        if len(shows) >= 6: break
        name = entry["im:name"]["label"].strip()
        author = entry.get("im:artist", {}).get("label", "").strip()
        images = entry.get("im:image", [])
        if not name or not author or not images: continue
        # The RSS thumb is 170px; the lookup API carries the 600px original.
        show_id = entry.get("id", {}).get("attributes", {}).get("im:id")
        art_url = images[-1]["label"]
        if show_id:
            try:
                results = get_json(f"https://itunes.apple.com/lookup?id={show_id}&country=RU")["results"]
                if results: art_url = results[0].get("artworkUrl600", art_url)
            except Exception:
                pass
        file_name = f"podcasts/pod{len(shows) + 1}.jpg"
        try:
            download(art_url, os.path.join(OUT, file_name))
        except Exception:
            continue
        shows.append({"file": file_name, "title": name[:44], "author": author[:40]})
        print(f"  {file_name} — {name[:40]}")
except Exception as e:
    print(f"  podcast directory unreachable ({e}); shows stay invented", file=sys.stderr)

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump({"albums": albums, "podcasts": shows}, f, ensure_ascii=False, indent=1)
with open(os.path.join(OUT, "LICENSES.txt"), "w") as f:
    f.write("Demo catalogue sources — Creative Commons / freely licensed releases:\n")
    f.write("\n".join(licences) + "\n")
print(f"manifest: {len(albums)} albums, {sum(len(a['tracks']) for a in albums)} tracks, {len(shows)} shows")
PYEOF
}

# ── Paintings mode: the v2 public-domain fallback, kept for offline work ─────
fetch_paintings() {
  rm -f "$OUT/manifest.json"   # paintings have no tracklists; the seed must invent
  local titles=(
    "Hilma af Klint Group IX SUW" "The Great Wave off Kanagawa"
    "Van Gogh - Starry Night - Google Art Project" "Wassily Kandinsky - Composition VIII"
    "Katsushika Hokusai - Fine Wind Clear Morning" "Ivan Aivazovsky - The Ninth Wave"
    "Kazimir Malevich - Suprematism" "Paul Klee - Castle and Sun"
  )
  local i=0
  for t in "${titles[@]}"; do
    i=$((i+1))
    local q url
    q=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$t")
    url=$(curl -sf -A "$UA" --max-time 25 \
      "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrsearch=$q&gsrnamespace=6&gsrlimit=1&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=800" \
      | python3 -c "
import json, sys
try:
    info = list(json.load(sys.stdin)['query']['pages'].values())[0]['imageinfo'][0]
    lic = info.get('extmetadata', {}).get('LicenseShortName', {}).get('value', '')
    print(info['thumburl'] if ('ublic domain' in lic or lic.startswith('PD')) else '')
except Exception: print('')")
    [ -n "$url" ] && curl -sf -A "$UA" --max-time 30 "$url" -o "$OUT/sleeve$i.jpg" && echo "  sleeve$i.jpg — $t"
    sleep 1
  done
}

echo "Demo catalogue → $OUT ($MODE)"
if [ "$MODE" = "real" ]; then fetch_real; else fetch_paintings; fi

for f in "$OUT"/*.jpg "$OUT"/podcasts/*.jpg; do [ -f "$f" ] && square "$f"; done

count=$(ls -1 "$OUT"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo "Done: $count sleeves$([ -f "$OUT/manifest.json" ] && echo ", manifest present")."
