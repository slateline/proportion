#!/usr/bin/env bash
# Build Proportion for the iOS Simulator and launch it — no Apple account,
# team, or signing needed. Run from a Mac with Xcode 16+ installed.
#
#   scripts/run-simulator.sh            # empty library, like a fresh install
#   scripts/run-simulator.sh --seed     # launch with sample recipes loaded
#   scripts/run-simulator.sh --device "iPhone 15"
#
# Installs XcodeGen via Homebrew if it is missing.
set -euo pipefail

DEVICE=""
SEED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED=1 ;;
    --device) shift; DEVICE="$1" ;;
    --device=*) DEVICE="${1#--device=}" ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  esac
  shift
done

cd "$(dirname "$0")/../App"

# The simulator ships only with full Xcode; the Command Line Tools alone
# can't build or run iOS apps.
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" != *"/Xcode"*".app/"* ]] || ! xcrun --find simctl >/dev/null 2>&1; then
  cat <<'EOF'
Xcode is not the active developer directory (found only the Command Line Tools).

  1. Install Xcode from the App Store (or https://developer.apple.com/xcode/), if you haven't.
  2. Open it once and let it finish installing components.
  3. Point the command-line tools at it:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
       sudo xcodebuild -license accept
  4. Run this script again.
EOF
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen…"
  brew install xcodegen
fi

echo "Generating Xcode project…"
xcodegen generate --quiet

# Pick a simulator: the one asked for, else the newest "Pro" iPhone, else any iPhone.
read -r UDID DEVICE < <(xcrun simctl list devices available -j | python3 -c "
import json, sys
wanted = '''$DEVICE'''
phones = [d for v in json.load(sys.stdin)['devices'].values() for d in v if d['name'].startswith('iPhone')]
def pick():
    if wanted:
        return next((d for d in phones if d['name'] == wanted), None)
    pro = [d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']]
    return (pro or phones or [None])[-1]
d = pick()
print(d['udid'], d['name']) if d else print('', '')
")
if [ -z "$UDID" ]; then
  echo "No available iPhone simulator${DEVICE:+ named '$DEVICE'}. Available:"
  xcrun simctl list devices available | grep iPhone || echo "  (none — open Xcode → Settings → Components and install an iOS simulator runtime)"
  exit 1
fi

echo "Building for simulator ($DEVICE)…"
DERIVED="$(pwd)/.derived"
xcodebuild \
  -project Proportion.xcodeproj \
  -scheme Proportion \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | grep -E --line-buffered 'error:|BUILD (SUCCEEDED|FAILED)' || true

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Proportion.app"
[ -d "$APP" ] || { echo "Build failed — see above."; exit 1; }

echo "Launching…"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
if [ "$SEED" = "1" ]; then
  xcrun simctl launch "$UDID" com.proportion.app -ui-testing >/dev/null
  echo "Running with sample recipes. (Data is in-memory and resets on relaunch.)"
else
  xcrun simctl launch "$UDID" com.proportion.app >/dev/null
  echo "Running with an empty library."
fi
