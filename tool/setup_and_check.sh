#!/bin/bash
# Pitbeat: installs Flutter if it is missing, finishes setting up the
# project, runs every check, then serves the web version on
# http://localhost:8765 so you can see it in Chrome.
#
# Run it from anywhere:
#   bash tool/setup_and_check.sh   (from the project folder)
#
# Everything it prints is also saved in build/checks/ so it can be read later.

cd "$(dirname "$0")/.." || exit 1
PROJECT="$(pwd)"
LOGS="$PROJECT/build/checks"
mkdir -p "$LOGS"
rm -f "$LOGS"/*.txt

step() { echo; echo "=============== $1 ==============="; }

step "1. Your Mac" 2>&1 | tee "$LOGS/1_mac.txt"
{
  sw_vers
  uname -m
  for tool in git python3 brew flutter xcodebuild pod; do
    printf '%-11s %s\n' "$tool" "$(command -v $tool || echo 'not found')"
  done
} 2>&1 | tee -a "$LOGS/1_mac.txt"

step "2. Flutter"
# Already installed by an earlier run of this script?
for dir in "$HOME/development/flutter/bin" "/opt/homebrew/bin"; do
  if ! command -v flutter >/dev/null 2>&1 && [ -x "$dir/flutter" ]; then
    export PATH="$dir:$PATH"
  fi
done
if ! command -v flutter >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  echo "Installing Flutter with Homebrew..."
  brew install --cask flutter 2>&1 | tee "$LOGS/2_install.txt"
  hash -r
  [ -x /opt/homebrew/bin/flutter ] && export PATH="/opt/homebrew/bin:$PATH"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter into ~/development/flutter with Git (a few minutes)..."
  mkdir -p "$HOME/development"
  # --filter=blob:none skips the old versions of every file, which makes the
  # download much smaller but keeps the history Flutter uses for its version.
  git clone --filter=blob:none https://github.com/flutter/flutter.git -b stable \
    "$HOME/development/flutter" 2>&1 | tee -a "$LOGS/2_install.txt"
  export PATH="$HOME/development/flutter/bin:$PATH"
  if ! grep -q 'development/flutter/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> "$HOME/.zshrc"
    echo "Added Flutter to your PATH in ~/.zshrc"
  fi
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter could not be installed. See build/checks/2_install.txt" | tee "$LOGS/2_failed.txt"
  exit 1
fi
flutter --version 2>&1 | tee "$LOGS/2_flutter_version.txt"
# Record whether macOS has put the SDK in quarantine (it blocks the engine tools).
FLUTTER_ROOT_REAL="$(cd "$(dirname "$(readlink -f "$(command -v flutter)")")/.." && pwd -P)"
echo "Flutter SDK folder: $FLUTTER_ROOT_REAL" | tee -a "$LOGS/2_flutter_version.txt"
echo "Quarantined files: $(xattr -rl "$FLUTTER_ROOT_REAL/bin/cache" 2>/dev/null | grep -c com.apple.quarantine)" | tee -a "$LOGS/2_flutter_version.txt"

step "3. Create the platform folders (keeps our lib/ and test/ files)"
flutter create --project-name pitbeat --org com.micmusonda \
  --platforms android,ios,web,macos . 2>&1 | tee "$LOGS/3_create.txt"

step "4. Add the packages"
flutter pub add http xml url_launcher shared_preferences 2>&1 | tee "$LOGS/4_packages.txt"
perl -pi -e 's/^description: .*/description: "A Formula 1 companion app: calendar, standings, race tracker and news."/' pubspec.yaml

step "5. Internet permissions"
MANIFEST=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ] && ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  perl -0pi -e 's#(<manifest[^>]*>)#$1\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$MANIFEST"
  echo "Android: added INTERNET permission"
fi
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  if [ -f "$f" ] && ! grep -q 'network.client' "$f"; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$f"
    echo "macOS: added network access to $f"
  fi
done

step "6. flutter analyze"
flutter analyze 2>&1 | tee "$LOGS/6_analyze.txt"
echo "exit code: ${PIPESTATUS[0]}" | tee -a "$LOGS/6_analyze.txt"

step "7. flutter test"
flutter test 2>&1 | tee "$LOGS/7_test.txt"
echo "exit code: ${PIPESTATUS[0]}" | tee -a "$LOGS/7_test.txt"

step "7b. Try the data layer in the terminal"
dart run bin/try_api.dart 2>&1 | tee "$LOGS/7b_try_api.txt"

step "8. flutter doctor"
flutter doctor -v 2>&1 | tee "$LOGS/8_doctor.txt"

step "9. API checks from your Mac"
{
  for url in \
    "https://api.jolpi.ca/ergast/f1/current/next.json" \
    "https://api.openf1.org/v1/sessions?session_key=latest" \
    "https://www.racefans.net/feed/" \
    "https://www.autosport.com/rss/f1/news/"; do
    echo "--- $url"
    curl -s -o /dev/null -D - -H "Origin: http://localhost:8765" "$url" | grep -i -E '^HTTP|access-control-allow-origin'
  done
  echo "--- RaceFans with the app's User-Agent"
  curl -s -o /dev/null -w "%{http_code}\n" -A "Mozilla/5.0 (Pitbeat)" "https://www.racefans.net/feed/"
  echo "--- A driver photo from formula1.com"
  curl -s -o /dev/null -w "%{http_code} %{content_type}\n" "https://media.formula1.com/d_driver_fallback_image.png/content/dam/fom-website/drivers/L/LEWHAM01_Lewis_Hamilton/lewham01.png.transform/1col/image.png"
  echo "--- OpenF1 date filter, typed as > and <"
  curl -s 'https://api.openf1.org/v1/location?session_key=9161&driver_number=81&date>2023-09-16T13:03:35.200Z&date<2023-09-16T13:03:35.800Z' | head -c 400; echo
  echo "--- OpenF1 date filter, encoded as %3E and %3C"
  curl -s 'https://api.openf1.org/v1/location?session_key=9161&driver_number=81&date%3E2023-09-16T13:03:35.200Z&date%3C2023-09-16T13:03:35.800Z' | head -c 400; echo
} 2>&1 | tee "$LOGS/9_api.txt"

step "10. Build the web version"
flutter build web 2>&1 | tee "$LOGS/10_build_web.txt"
echo "exit code: ${PIPESTATUS[0]}" | tee -a "$LOGS/10_build_web.txt"

step "10b. Build the iPhone version (no signing, just checks it compiles)"
if command -v xcodebuild >/dev/null 2>&1; then
  flutter build ios --no-codesign --debug 2>&1 | tee "$LOGS/10b_build_ios.txt"
  echo "exit code: ${PIPESTATUS[0]}" | tee -a "$LOGS/10b_build_ios.txt"
fi

echo "done" > "$LOGS/finished.txt"

step "11. Serving the app"
if lsof -iTCP:8765 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Something is already serving on port 8765 (probably an earlier run of this script)."
  echo "Just open http://localhost:8765 in Chrome and refresh the page."
else
  echo "Open http://localhost:8765 in Chrome. Leave this window open. Press Ctrl+C to stop."
  cd build/web && python3 -m http.server 8765
fi
