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

DEVICE="iPhone 16 Pro"
SEED=0
for arg in "$@"; do
  case "$arg" in
    --seed) SEED=1 ;;
    --device) shift; DEVICE="$1" ;;
    --device=*) DEVICE="${arg#--device=}" ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  esac
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

UDID=$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next((x['udid'] for v in d.values() for x in v if x['name']=='$DEVICE'),''))")
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE'. Available iPhones:"
  xcrun simctl list devices available | grep iPhone
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
