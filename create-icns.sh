#!/bin/bash
# Create AppIcon.icns from the SF Symbol icon
# This script requires iconutil (built into macOS)

set -e

ICON_DIR="TablePro/AppIcon.icon"
SVG_FILE="$ICON_DIR/Assets/cylinder.split.1x2.fill 1.svg"
OUTPUT_ICONSET="TablePro/Assets.xcassets/AppIcon.appiconset/AppIcon.iconset"
OUTPUT_ICNS="TablePro/Assets.xcassets/AppIcon.appiconset/AppIcon.icns"

echo "🎨 Creating AppIcon.icns from SF Symbol..."

# Check if SVG exists
if [ ! -f "$SVG_FILE" ]; then
    echo "❌ ERROR: SVG file not found: $SVG_FILE"
    exit 1
fi

# Create temporary iconset directory
rm -rf "$OUTPUT_ICONSET"
mkdir -p "$OUTPUT_ICONSET"

# Check if rsvg-convert is available (part of librsvg)
if ! command -v rsvg-convert &> /dev/null; then
    echo "⚠️  rsvg-convert not found. Installing librsvg..."
    if command -v brew &> /dev/null; then
        brew install librsvg
    else
        echo "❌ ERROR: Homebrew not found. Please install librsvg manually."
        echo "   Run: brew install librsvg"
        exit 1
    fi
fi

# Generate PNG files at all required sizes
# macOS icon sizes: 16, 32, 128, 256, 512, 1024 (and @2x versions)
sizes=(16 32 128 256 512)

echo "📐 Generating icon sizes..."

for size in "${sizes[@]}"; do
    # 1x version
    rsvg-convert -w "$size" -h "$size" "$SVG_FILE" > "$OUTPUT_ICONSET/icon_${size}x${size}.png"
    echo "  ✓ icon_${size}x${size}.png"

    # 2x version
    size2x=$((size * 2))
    rsvg-convert -w "$size2x" -h "$size2x" "$SVG_FILE" > "$OUTPUT_ICONSET/icon_${size}x${size}@2x.png"
    echo "  ✓ icon_${size}x${size}@2x.png"
done

# 1024x1024 (no @2x version)
rsvg-convert -w 1024 -h 1024 "$SVG_FILE" > "$OUTPUT_ICONSET/icon_512x512@2x.png"
echo "  ✓ icon_512x512@2x.png (1024x1024)"

echo ""
echo "🔧 Creating .icns file..."

# Use iconutil to create .icns file
iconutil -c icns "$OUTPUT_ICONSET" -o "$OUTPUT_ICNS"

# Clean up iconset directory
rm -rf "$OUTPUT_ICONSET"

echo ""
echo "✅ AppIcon.icns created successfully!"
echo "   Location: $OUTPUT_ICNS"
echo ""
echo "📋 Next steps:"
echo "   1. Open Xcode project"
echo "   2. Rebuild the app"
echo "   3. The icon should now appear correctly"
