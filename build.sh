#!/bin/sh
# Builds a universal (Apple silicon + Intel) Wakeful.app for macOS 11+ and zips it.
#
#   ./build.sh                                   ad-hoc signed, for local testing
#   SIGN_ID=<Developer ID sha1> ./build.sh       Developer ID + hardened runtime
#   SIGN_ID=... NOTARY_PROFILE=svar-notary ./build.sh   ...and notarized + stapled
#
# Output: build/Wakeful.app and build/Wakeful-<version>.zip
set -e
cd "$(dirname "$0")"
./scripts/fetch-sparkle.sh

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP=build/Wakeful.app
ZIP=build/Wakeful-$VERSION.zip
SPARKLE=vendor/Sparkle/Sparkle.framework
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"

for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos11.0" \
    -F vendor/Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -framework AppKit -framework SwiftUI -framework IOKit \
    Sources/*.swift -o "build/Wakeful-$arch"
done
lipo -create build/Wakeful-arm64 build/Wakeful-x86_64 -output "$APP/Contents/MacOS/Wakeful"
rm build/Wakeful-arm64 build/Wakeful-x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

# Sign inside-out, as Sparkle's docs recommend.
SIGN_ID="${SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  sign() { codesign --force --sign - "$@"; }
else
  sign() { codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@"; }
fi
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/Wakeful.entitlements "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  spctl --assess --type execute -vv "$APP"
fi
echo "Built $APP and $ZIP"
