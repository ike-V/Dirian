#!/bin/bash
# Builds and ad-hoc signs Dirian.app. Ad-hoc signing runs locally; other Macs
# will flag the app as untrusted.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Compiling..."
swift build -c release

APP="Dirian.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Diroid "$APP/Contents/MacOS/Diroid"
# Sets the minimum macOS (13.0) and the SDK version (the installed one).
vtool -set-build-version macos 13.0 "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/Diroid" "$APP/Contents/MacOS/Diroid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Compiles the Icon Composer icon into Assets.car (macOS 26+) and a Dirian.icns fallback.
ICON_OUT="$(mktemp -d)"
xcrun actool "$PWD/Resources/Dirian.icon" --compile "$ICON_OUT" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon Dirian \
    --output-partial-info-plist "$ICON_OUT/partial.plist" > /dev/null
cp "$ICON_OUT/Assets.car" "$ICON_OUT/Dirian.icns" "$APP/Contents/Resources/"
cp Resources/DirianClassic.png Resources/DirianClassicDark.png "$APP/Contents/Resources/"
rm -rf "$ICON_OUT"

echo "==> Code-signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "==> Done: $APP"
