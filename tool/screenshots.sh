#!/bin/zsh
# Retakes the README screenshots in docs/screenshots from the demo watch, on the iOS simulator that is booted.
# Run from the repository root on a Mac: tool/screenshots.sh
set -euo pipefail

bundle=app.wristore.galaxyWristore
out=docs/screenshots
raw=$(mktemp -d)
# name:tab:page, using the WRISTORE_TAB and WRISTORE_OPEN switches in lib/app/app.dart.
shots=(watch:watch: faces:faces: face:faces:face apps:apps: discover:discover: package:discover:package
  backup:backup: restore:backup:restore)

xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
mkdir -p $out
for shot in $shots; do
  name=${shot%%:*} rest=${shot#*:}
  tab=${rest%%:*} page=${rest#*:}
  flutter build ios --simulator --debug --dart-define=WRISTORE_DEMO=true \
    --dart-define=WRISTORE_TAB=$tab --dart-define=WRISTORE_OPEN=$page >/dev/null
  xcrun simctl uninstall booted $bundle 2>/dev/null || true
  xcrun simctl install booted build/ios/iphonesimulator/Runner.app
  xcrun simctl launch booted $bundle >/dev/null
  sleep 9 # The demo watch connects and its pictures load.
  xcrun simctl io booted screenshot $raw/$name.png >/dev/null 2>&1
  sips --resampleWidth 600 $raw/$name.png --out $out/$name.png >/dev/null
  echo "$out/$name.png"
done
xcrun simctl status_bar booted clear
rm -rf $raw
