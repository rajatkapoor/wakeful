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

codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent Wakeful.app Wakeful.zip)
echo "Built $APP and build/Wakeful.zip"
