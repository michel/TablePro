#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:?Usage: verify-build.sh <arch>}"

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  echo "❌ ERROR: Invalid architecture: $ARCH (expected arm64 or x86_64)"
  exit 1
fi

if [[ "$ARCH" == "arm64" ]]; then
  OPPOSITE_ARCH="x86_64"
else
  OPPOSITE_ARCH="arm64"
fi

echo "Verifying build output..."

BINARY_PATH="build/Release/TablePro-${ARCH}.app/Contents/MacOS/TablePro"

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
  echo "❌ ERROR: Built binary not found at: $BINARY_PATH"
  echo "Build may have failed silently"
  exit 1
fi

# Check it's not empty
if [ ! -s "$BINARY_PATH" ]; then
  echo "❌ ERROR: Binary file is empty"
  exit 1
fi

# Check architecture
ARCH_INFO=$(lipo -info "$BINARY_PATH")
echo "Architecture: $ARCH_INFO"

if ! echo "$ARCH_INFO" | grep -q "$ARCH"; then
  echo "❌ ERROR: Binary does not contain $ARCH architecture"
  echo "Expected: $ARCH only"
  echo "Got: $ARCH_INFO"
  exit 1
fi

if echo "$ARCH_INFO" | grep -q "$OPPOSITE_ARCH"; then
  echo "❌ ERROR: Binary contains $OPPOSITE_ARCH but should be $ARCH only"
  exit 1
fi

# Check it's executable
if [ ! -x "$BINARY_PATH" ]; then
  echo "❌ ERROR: Binary is not executable"
  exit 1
fi

# Verify bundled dylibs
FRAMEWORKS_DIR="build/Release/TablePro-${ARCH}.app/Contents/Frameworks"
if [ -d "$FRAMEWORKS_DIR" ]; then
  echo "Bundled dynamic libraries:"
  ls -lh "$FRAMEWORKS_DIR"/*.dylib 2>/dev/null || echo "  (none)"

  # Verify no Homebrew paths remain in the binary
  if otool -L "$BINARY_PATH" | grep -q '/opt/homebrew/\|/usr/local/opt/'; then
    echo "❌ ERROR: Binary still references Homebrew paths:"
    otool -L "$BINARY_PATH" | grep '/opt/homebrew/\|/usr/local/opt/'
    exit 1
  fi
  echo "✅ No Homebrew path references in binary"
else
  echo "⚠️  WARNING: No Frameworks directory found — dylibs may not be bundled"
fi

# Display info
echo "✅ Build verified successfully"
echo "Binary size: $(ls -lh "$BINARY_PATH" | awk '{print $5}')"
echo "App bundle size: $(du -sh "build/Release/TablePro-${ARCH}.app" | awk '{print $1}')"
