#!/bin/sh
# Downloads the pinned Sparkle release into vendor/Sparkle (framework + bin/ tools).
set -e
cd "$(dirname "$0")/.."
VERSION=2.8.1
DEST=vendor/Sparkle
[ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ] && exit 0
rm -rf "$DEST" && mkdir -p "$DEST"
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$DEST/sparkle.tar.xz"
tar -xJf "$DEST/sparkle.tar.xz" -C "$DEST"
rm "$DEST/sparkle.tar.xz"
echo "$VERSION" > "$DEST/.version"
