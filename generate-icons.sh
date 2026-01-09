#!/bin/bash
# Generate app icons from SF Symbol SVG

set -e

SVG_FILE="TablePro/AppIcon.icon/Assets/cylinder.split.1x2.fill 1.svg"
OUTPUT_DIR="TablePro/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SVG_FILE" ]; then
    echo "❌ ERROR: SVG file not found: $SVG_FILE"
    exit 1
fi

echo "🎨 Generating app icons from SF Symbol..."

# Create temporary directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Function to generate PNG from SVG using sips/qlmanage
generate_png() {
    local size=$1
    local output=$2

    # Use qlmanage to convert SVG to PNG (available on macOS)
    # First create a temporary high-res PNG, then resize
    qlmanage -t -s 1024 -o "$TMP_DIR" "$SVG_FILE" > /dev/null 2>&1

    # Get the generated file (qlmanage adds .png extension)
    local temp_png=$(find "$TMP_DIR" -name "*.png" | head -1)

    if [ -f "$temp_png" ]; then
        # Resize using sips
        sips -z "$size" "$size" "$temp_png" --out "$output" > /dev/null 2>&1
        echo "  ✓ Created ${size}x${size} icon"
    else
        echo "  ❌ Failed to create ${size}x${size} icon"
        return 1
    fi

    # Clean temp files
    rm -f "$temp_png"
}

# Note: macOS doesn't have imagemagick by default, so we'll use the .icon format
# and create a proper icns file instead

echo ""
echo "⚠️  Note: This script requires ImageMagick to generate icons."
echo "   Install with: brew install imagemagick"
echo ""
echo "Alternative: Use the AppIcon.icon format which is already configured."
echo "The issue is that the build process needs to properly compile it."
echo ""
echo "Recommended fix: Update the Xcode project to use CFBundleIconFile = AppIcon"

# Check if ImageMagick is available
if ! command -v convert &> /dev/null; then
    echo ""
    echo "❌ ImageMagick not found. Installing..."
    echo "   Run: brew install imagemagick"
    exit 1
fi

# Generate all required sizes
sizes=(16 32 128 256 512 1024)

for size in "${sizes[@]}"; do
    generate_png "$size" "$OUTPUT_DIR/icon_${size}x${size}.png"

    # Generate @2x versions
    if [ "$size" != "1024" ]; then
        local size2x=$((size * 2))
        generate_png "$size2x" "$OUTPUT_DIR/icon_${size}x${size}@2x.png"
    fi
done

echo ""
echo "✅ Icon generation complete!"
echo "   Icons saved to: $OUTPUT_DIR"
