#!/bin/bash
# Build GistUploader and install it to /Applications, then register the
# Xcode Source Editor Extension with PluginKit.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Building (Release)…"
xcodebuild -project GistUploader.xcodeproj -target GistUploader \
  -configuration Release SYMROOT="$PWD/build" -allowProvisioningUpdates build \
  | grep -E "Signing Identity|error|BUILD" || true

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

echo "==> Installing to /Applications…"
osascript -e 'tell application "GistUploader" to quit' 2>/dev/null || true
rm -rf /Applications/GistUploader.app
ditto build/Release/GistUploader.app /Applications/GistUploader.app

echo "==> Registering the extension…"
# xcodebuild auto-registers the build-dir copy; remove it so System Settings
# doesn't show duplicates.
"$LSREGISTER" -u "$PWD/build/Release/GistUploader.app" 2>/dev/null || true
"$LSREGISTER" -f /Applications/GistUploader.app
pluginkit -a /Applications/GistUploader.app/Contents/PlugIns/GistUploaderExtension.appex
pluginkit -e use -i com.swiftruru.GistUploader.Extension || true
# Recycle any running extension process so Xcode picks up the new binary.
pkill -f GistUploaderExtension.appex 2>/dev/null || true

echo
pluginkit -m -v -i com.swiftruru.GistUploader.Extension || true
echo
echo "Done. If this is the first install:"
echo "  1. Check 'Gist Uploader' in System Settings → General → Login Items & Extensions → Xcode Source Editor."
echo "  2. Restart Xcode. The commands appear at the bottom of the Editor menu."
