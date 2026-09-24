#!/bin/bash
# Pitbeat: get the app running on the iPhone simulator.
# Run it from the project folder:  bash tool/run_iphone.sh
# Logs go to build/checks/ if something fails.

set -o pipefail
cd "$(dirname "$0")/.." || exit 1
LOG=build/checks
mkdir -p "$LOG"

# Xcode cannot sign an app inside a folder that iCloud (or OneDrive, Dropbox,
# Google Drive) syncs: the sync adds hidden Finder data that codesign refuses.
case "$PWD" in
  "$HOME/Documents"*|"$HOME/Desktop"*|*"Mobile Documents"*|*CloudStorage*)
    echo
    echo "Warning: this project is in $PWD"
    echo "If iCloud syncs your Desktop and Documents, the iPhone build will fail here."
    echo "Safer place:  mkdir -p ~/Developer && mv \"$PWD\" ~/Developer/"
    ;;
esac

echo
echo "== 1. Has Xcode finished its first-launch setup? =="
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  echo "Not yet. Run this once, type your Mac password, then run this script again:"
  echo "   sudo xcodebuild -runFirstLaunch"
  exit 1
fi
echo "Yes."

echo
echo "== 2. Which iOS version does Xcode build for? =="
SDK=$(xcodebuild -showsdks 2>/dev/null | grep -o 'iphonesimulator[0-9.]*' | sed 's/iphonesimulator//' | head -1)
MAJOR=${SDK%%.*}
if [ -z "$MAJOR" ]; then
  echo "Could not read Xcode's iOS SDK. Open Xcode once, let it finish installing, then try again."
  exit 1
fi
echo "Xcode builds for iOS $SDK"

echo
echo "== 3. Is the iOS $MAJOR platform installed? =="
xcrun simctl list runtimes > "$LOG/11_runtimes.txt" 2>&1
cat "$LOG/11_runtimes.txt"
if grep -q "iOS $MAJOR\." "$LOG/11_runtimes.txt"; then
  echo "Yes."
else
  echo "No. Downloading it now (several GB, this can take 10 to 30 minutes)..."
  xcodebuild -downloadPlatform iOS 2>&1 | tee "$LOG/11b_download_platform.txt"
  xcrun simctl list runtimes > "$LOG/11_runtimes.txt" 2>&1
  if ! grep -q "iOS $MAJOR\." "$LOG/11_runtimes.txt"; then
    echo "The download did not finish. Open Xcode > Settings > Components, click Get next to iOS $MAJOR, then run this script again."
    exit 1
  fi
fi

echo
echo "== 4. Build Pitbeat for the simulator =="
if ! flutter build ios --simulator --debug 2>&1 | tee "$LOG/12_build_ios_sim.txt"; then
  echo
  echo "Build failed. Saving the full Xcode output..."
  flutter build ios --simulator --debug -v > "$LOG/12b_build_ios_verbose.txt" 2>&1
  if grep -q "detritus not allowed" "$LOG/12b_build_ios_verbose.txt"; then
    NAME=$(basename "$PWD")
    echo "Cause: this folder is synced by iCloud (or another cloud drive). The sync adds"
    echo "hidden Finder data to the build files, and Xcode refuses to sign them."
    echo "Fix: move the project somewhere that is not synced, then run this again:"
    echo "   mkdir -p ~/Developer && mv \"$PWD\" ~/Developer/"
    echo "   cd ~/Developer/$NAME && flutter clean && bash tool/run_iphone.sh"
    exit 1
  fi
  grep -iE "error|fatal" "$LOG/12b_build_ios_verbose.txt" | tail -15
  echo
  echo "The full Xcode output is in build/checks/12b_build_ios_verbose.txt."
  exit 1
fi

echo
echo "== 5. Start an iPhone simulator =="
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
ios = [k for k in data if ".SimRuntime.iOS-" in k]
ios.sort(key=lambda k: [int(p) for p in k.split("iOS-")[1].split("-")])
for runtime in reversed(ios):
    phones = [d for d in data[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"])
        break
')
if [ -z "$DEVICE" ]; then
  echo "No iPhone simulator found. In Xcode: Window > Devices and Simulators > Simulators > + to add one."
  exit 1
fi
xcrun simctl list devices | grep "$DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null
# The window that shows the iPhone. Xcode 27 renamed the Simulator app to
# Device Hub, so try the new name first, then the old ones.
open -a "Device Hub" 2>/dev/null \
  || open -a Simulator 2>/dev/null \
  || open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null \
  || echo "Open it from Xcode: Xcode > Open Developer Tool > Device Hub (or Simulator)."
echo "Can't see the iPhone? If VS Code or Terminal is full screen, the window opened"
echo "on your normal desktop: press Cmd+Tab and choose Device Hub."

echo
echo "== 6. Run Pitbeat on the iPhone =="
echo "Keys while it runs:  r = hot reload,  R = full restart,  q = quit"
echo "The first launch on a new simulator prints hundreds of system log lines"
echo "(WFToolKit, Skipping, TIMEOUT...). That is iOS setting itself up, not your app."
flutter run -d "$DEVICE"
