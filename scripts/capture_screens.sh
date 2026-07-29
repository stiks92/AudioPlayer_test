#!/usr/bin/env bash
#
# Capture every screen of Sonava into a folder, for design review.
#
# The design-critic agent judges rendered pixels, not descriptions, so this has
# to be repeatable: same device, same seeded data, same order every time. That
# is also what makes two runs comparable when checking whether a fix landed.
#
#   scripts/capture_screens.sh <output-dir> [en|ru] [free|pro]
#
# Requires the app to be built already:
#   xcodebuild -project Sonava.xcodeproj -scheme Sonava \
#     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
#
set -euo pipefail

OUT="${1:?usage: capture_screens.sh <output-dir> [en|ru] [free|pro]}"
LANG_CODE="${2:-en}"
TIER="${3:-pro}"
DEVICE="${DEVICE:-iPhone 17 Pro}"
BUNDLE="com.sonava.player"

LOCALE="en_US"
[ "$LANG_CODE" = "ru" ] && LOCALE="ru_RU"
PRO="NO"
[ "$TIER" = "pro" ] && PRO="YES"

UDID=$(xcrun simctl list devices available --json \
  | python3 -c "import json,sys;print([d['udid'] for v in json.load(sys.stdin)['devices'].values() for d in v if d['name']=='$DEVICE'][0])")

# -sdk matters: without it the build settings resolve to the device products
# directory, which does not exist for a simulator-only build.
APP=$(xcodebuild -project Sonava.xcodeproj -scheme Sonava -sdk iphonesimulator \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Sonava.app

mkdir -p "$OUT"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

# Pin the things that silently change what a screenshot measures.
#
# Two capture runs were once compared for text contrast and the count moved by
# 93 rows on screens nobody had touched. The cause was the text size: erasing a
# simulator resets its content size category, so the two sets were rendered at
# different type scales and the comparison was void — glyphs occupying more
# sampled rows, not worse contrast. A run-to-run delta only means something if
# everything except the code is held still.
xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" appearance dark >/dev/null 2>&1 || true

# Shared arguments: skip onboarding, fix the language, seed everything the
# screens need so no shelf is empty for reasons unrelated to design.
COMMON=(-hasOnboarded.v1 YES -pro.dev.override.v1 "$PRO"
        -AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE"
        -seedDemoContent -seedStats -seedServers 3)

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "${COMMON[@]}" "$@" >/dev/null
  sleep "${SETTLE:-4}"
  xcrun simctl io "$UDID" screenshot "$OUT/${name}.png" >/dev/null 2>&1
  echo "  $name"
}

echo "Capturing $LANG_CODE/$TIER → $OUT"

# Tabs. A track is playing throughout so the mini player is in every shot —
# it is part of the layout, not an overlay to review separately.
shot "01-home"      -openTab home -demoPlay
shot "02-search"    -openTab search
shot "03-radio"     -openTab radio
shot "04-podcasts"  -openTab podcasts
shot "05-library"   -openTab library

# Sheets and secondary screens
shot "06-settings"  -openSettings
shot "07-stats"     -openStats
shot "08-servers"   -openServers
shot "09-equalizer" -openEqualizer
shot "10-paywall"   -openPaywall
shot "11-aimix"     -openAIMix
shot "12-scrobble"  -openScrobble

# Onboarding runs off a different flag, so it goes last and on its own.
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE" -hasOnboarded.v1 NO \
  -AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE" >/dev/null
sleep 4
xcrun simctl io "$UDID" screenshot "$OUT/13-onboarding.png" >/dev/null 2>&1
echo "  13-onboarding"

echo "Done: $(ls -1 "$OUT" | wc -l | tr -d ' ') screenshots in $OUT"
