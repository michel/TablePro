#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: update-homebrew.sh <version> <staging_dir>}"
STAGING="${2:?Usage: update-homebrew.sh <version> <staging_dir>}"

if [ -z "${HOMEBREW_TAP_TOKEN:-}" ]; then
  echo "❌ ERROR: HOMEBREW_TAP_TOKEN environment variable is not set"
  exit 1
fi

echo "Updating Homebrew tap for TablePro v${VERSION}..."

ARM64_DMG="${STAGING}/TablePro-${VERSION}-arm64.dmg"
X86_64_DMG="${STAGING}/TablePro-${VERSION}-x86_64.dmg"

# Download DMGs if not in staging (fallback)
if [ ! -f "$ARM64_DMG" ]; then
  echo "Downloading arm64 DMG from release..."
  mkdir -p "$STAGING"
  curl -fsSL -o "$ARM64_DMG" "https://github.com/datlechin/TablePro/releases/download/v${VERSION}/TablePro-${VERSION}-arm64.dmg"
fi
if [ ! -f "$X86_64_DMG" ]; then
  echo "Downloading x86_64 DMG from release..."
  mkdir -p "$STAGING"
  curl -fsSL -o "$X86_64_DMG" "https://github.com/datlechin/TablePro/releases/download/v${VERSION}/TablePro-${VERSION}-x86_64.dmg"
fi

# Compute SHA256
ARM64_SHA=$(shasum -a 256 "$ARM64_DMG" | awk '{print $1}')
X86_64_SHA=$(shasum -a 256 "$X86_64_DMG" | awk '{print $1}')
echo "ARM64 SHA256: $ARM64_SHA"
echo "x86_64 SHA256: $X86_64_SHA"

# Clone tap repo
HOMEBREW_TAP_DIR=$(mktemp -d)
git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/datlechin/homebrew-tap.git" "$HOMEBREW_TAP_DIR"
cd "$HOMEBREW_TAP_DIR"

# Update cask formula
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" Casks/tablepro.rb
sed -i '' "s/sha256 arm:   \"[a-f0-9]*\"/sha256 arm:   \"${ARM64_SHA}\"/" Casks/tablepro.rb
sed -i '' "s/intel: \"[a-f0-9]*\"/intel: \"${X86_64_SHA}\"/" Casks/tablepro.rb

# Commit and push
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/tablepro.rb
git diff --cached --quiet && echo "No changes to cask formula" && exit 0
git commit -m "Update TablePro to v${VERSION}"
git push origin main

# Cleanup
rm -rf "$HOMEBREW_TAP_DIR"
echo "✅ Homebrew tap updated to v${VERSION}"
