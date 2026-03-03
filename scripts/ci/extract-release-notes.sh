#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: extract-release-notes.sh <version>}"

echo "Extracting release notes for version: $VERSION"

# Extract the section for this version from CHANGELOG.md
# Matches from "## [X.Y.Z]" until the next "## [" or end of file
NOTES=$(awk -v ver="$VERSION" '
  /^## \[/ {
    if (found) exit
    if ($0 ~ "\\[" ver "\\]") { found=1; next }
  }
  found { print }
' CHANGELOG.md)

if [ -z "$NOTES" ]; then
  echo "⚠️  No changelog entry found for version $VERSION, using fallback"
  echo "- Bug fixes and improvements" > release_notes.md
else
  echo "$NOTES" > release_notes.md
fi

echo "✅ Release notes extracted"
cat release_notes.md
