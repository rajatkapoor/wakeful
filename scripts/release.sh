#!/bin/sh
# Builds, signs, notarizes and publishes a release that existing installs pick up automatically.
#
#   1. Bump CFBundleShortVersionString and CFBundleVersion (+1) in Resources/Info.plist, commit.
#   2. scripts/release.sh "What changed in this version"
#
# The zip + appcast.xml are attached to a GitHub release on this (public) repo, which is where
# Sparkle (SUFeedURL) looks: releases/latest/download/appcast.xml.
#
# Environment (defaults shown):
#   SIGN_ID=890FA343CE318ACF071F9E588B18A2CD442B1A7E   Developer ID Application certificate
#   NOTARY_PROFILE=svar-notary                         notarytool keychain profile (any app, same team)
#   RELEASES_REPO=rajatkapoor/wakeful
# The EdDSA update-signing key lives in the login keychain (Sparkle account "wakeful").
set -e
cd "$(dirname "$0")/.."
NOTES="${1:-Bug fixes and improvements.}"
export SIGN_ID="${SIGN_ID:-890FA343CE318ACF071F9E588B18A2CD442B1A7E}"
export NOTARY_PROFILE="${NOTARY_PROFILE:-svar-notary}"
RELEASES_REPO="${RELEASES_REPO:-rajatkapoor/wakeful}"

[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
BUILD=$(plutil -extract CFBundleVersion raw Resources/Info.plist)
MIN_OS=$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)
TAG="v$VERSION"
gh release view "$TAG" -R "$RELEASES_REPO" >/dev/null 2>&1 && { echo "$TAG already exists in $RELEASES_REPO. Bump the version."; exit 1; }

./build.sh
ZIP="build/Wakeful-$VERSION.zip"
SIG_ATTRS=$(vendor/Sparkle/bin/sign_update --account wakeful "$ZIP")
NOTES_HTML=$(printf '%s' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')

cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Wakeful</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES_HTML</p>]]></description>
      <enclosure url="https://github.com/$RELEASES_REPO/releases/download/$TAG/Wakeful-$VERSION.zip" type="application/octet-stream" $SIG_ATTRS />
    </item>
  </channel>
</rss>
EOF

(cd build && shasum -a 256 "Wakeful-$VERSION.zip" > SHA256SUMS.txt)
git tag -f "$TAG" && git push -q origin HEAD "$TAG" --force
gh release create "$TAG" -R "$RELEASES_REPO" "$ZIP" build/appcast.xml build/SHA256SUMS.txt \
  --title "Wakeful $VERSION" --notes "$NOTES

Universal (Apple silicon + Intel), macOS $MIN_OS or later. Signed with Developer ID and notarized by Apple.
Install: download Wakeful-$VERSION.zip, unzip, move Wakeful.app to Applications. Existing installs update themselves."
echo "Released $TAG to https://github.com/$RELEASES_REPO/releases/tag/$TAG"
