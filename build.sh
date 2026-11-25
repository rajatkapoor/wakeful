#!/bin/sh
# Builds a universal (Apple silicon + Intel) Wakeful.app for macOS 11+ and zips it for other Macs.
set -e
cd "$(dirname "$0")"
APP=build/Wakeful.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos11.0" \
    -framework AppKit -framework SwiftUI -framework IOKit \
    Sources/*.swift -o "build/Wakeful-$arch"
done
lipo -create build/Wakeful-arm64 build/Wakeful-x86_64 -output "$APP/Contents/MacOS/Wakeful"
rm build/Wakeful-arm64 build/Wakeful-x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"

# SIGN_ID: a "Developer ID Application" identity (defaults to ad-hoc "-").
# NOTARY_PROFILE: a profile saved with `xcrun notarytool store-credentials` (optional).
SIGN_ID="${SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements Resources/Wakeful.entitlements --sign "$SIGN_ID" "$APP"
fi
codesign --verify --strict "$APP"

(cd build && ditto -c -k --keepParent Wakeful.app Wakeful.zip)

if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit build/Wakeful.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm build/Wakeful.zip
  (cd build && ditto -c -k --keepParent Wakeful.app Wakeful.zip)
  spctl --assess --type execute -vv "$APP"
fi
echo "Built $APP and build/Wakeful.zip"
