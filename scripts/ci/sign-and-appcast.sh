#!/usr/bin/env bash
set -euo pipefail

# Signs release archives with Sparkle EdDSA and generates/updates appcast.xml.
#
# Usage: sign-and-appcast.sh <version>
# Requires: SPARKLE_PRIVATE_KEY env var, artifacts/ directory with ZIPs.
#
# The appcast.xml preserves history — new items are prepended to the existing
# feed so Sparkle shows cumulative release notes for users skipping versions.

VERSION="${1:?Usage: sign-and-appcast.sh <version>}"

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "❌ ERROR: SPARKLE_PRIVATE_KEY environment variable is not set"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Locate Sparkle tools
# ---------------------------------------------------------------------------
brew list --cask sparkle &>/dev/null || brew install --cask sparkle
SPARKLE_BIN="$(brew --caskroom)/sparkle/$(ls "$(brew --caskroom)/sparkle" | head -1)/bin"

# ---------------------------------------------------------------------------
# 2. Sign archives with EdDSA
# ---------------------------------------------------------------------------
ARM64_ZIP="artifacts/TablePro-${VERSION}-arm64.zip"
X86_64_ZIP="artifacts/TablePro-${VERSION}-x86_64.zip"

KEY_FILE=$(mktemp)
trap 'rm -f "$KEY_FILE"' EXIT
echo "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"

parse_sig() {
  local output="$1" field="$2"
  echo "$output" | sed -n "s/.*${field}=\"\\([^\"]*\\)\".*/\\1/p"
}

ARM64_SIG=$("$SPARKLE_BIN/sign_update" "$ARM64_ZIP" -f "$KEY_FILE")
X86_64_SIG=$("$SPARKLE_BIN/sign_update" "$X86_64_ZIP" -f "$KEY_FILE")

ARM64_ED_SIG=$(parse_sig "$ARM64_SIG" "sparkle:edSignature")
ARM64_LENGTH=$(parse_sig "$ARM64_SIG" "length")
X86_64_ED_SIG=$(parse_sig "$X86_64_SIG" "sparkle:edSignature")
X86_64_LENGTH=$(parse_sig "$X86_64_SIG" "length")

# ---------------------------------------------------------------------------
# 3. Extract version metadata from the built app
# ---------------------------------------------------------------------------
TEMP_DIR=$(mktemp -d)
unzip -q "$ARM64_ZIP" -d "$TEMP_DIR"
INFO_PLIST=$(find "$TEMP_DIR" -maxdepth 3 -path "*/Contents/Info.plist" | head -1)

if [ -n "$INFO_PLIST" ] && [ -f "$INFO_PLIST" ]; then
  BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "1")
  SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "$VERSION")
  MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || echo "14.0")
else
  echo "⚠️  Could not find app Info.plist in ZIP, using defaults"
  BUILD_NUMBER="1"
  SHORT_VERSION="$VERSION"
  MIN_OS="14.0"
fi
rm -rf "$TEMP_DIR"

# ---------------------------------------------------------------------------
# 4. Extract release notes from CHANGELOG.md → HTML
# ---------------------------------------------------------------------------
if [ -f release_notes.md ]; then
    NOTES=$(cat release_notes.md)
else
    NOTES=$(awk "/^## \\[${VERSION}\\]/{flag=1; next} /^## \\[/{flag=0} flag" CHANGELOG.md)
fi

if [ -z "$NOTES" ]; then
  RELEASE_HTML="<li>Bug fixes and improvements</li>"
else
  RELEASE_HTML=$(echo "$NOTES" | sed -E \
    -e 's/^### (.+)$/<h3>\1<\/h3>/' \
    -e 's/^- (.+)$/<li>\1<\/li>/' \
    -e '/^[[:space:]]*$/d' \
  | awk '
    /<li>/ {
      if (!in_list) { print "<ul>"; in_list=1 }
      print; next
    }
    {
      if (in_list) { print "</ul>"; in_list=0 }
      print
    }
    END { if (in_list) print "</ul>" }
  ')
fi

DESCRIPTION_HTML="<body style=\"font-family: -apple-system, sans-serif; font-size: 13px; padding: 8px;\">${RELEASE_HTML}</body>"

# ---------------------------------------------------------------------------
# 5. Build appcast.xml — merge new items into existing feed
# ---------------------------------------------------------------------------
DOWNLOAD_PREFIX="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-TableProApp/TablePro}/releases/download/v${VERSION}"
PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
EXISTING_APPCAST="appcast.xml"

mkdir -p appcast

python3 scripts/ci/update-appcast.py \
  --output appcast/appcast.xml \
  --existing "$EXISTING_APPCAST" \
  --version "$SHORT_VERSION" \
  --build "$BUILD_NUMBER" \
  --min-os "$MIN_OS" \
  --pub-date "$PUB_DATE" \
  --description "$DESCRIPTION_HTML" \
  --arm64-url "${DOWNLOAD_PREFIX}/TablePro-${VERSION}-arm64.zip" \
  --arm64-length "$ARM64_LENGTH" \
  --arm64-sig "$ARM64_ED_SIG" \
  --x86-url "${DOWNLOAD_PREFIX}/TablePro-${VERSION}-x86_64.zip" \
  --x86-length "$X86_64_LENGTH" \
  --x86-sig "$X86_64_ED_SIG"

echo "✅ Appcast generated:"
cat appcast/appcast.xml
