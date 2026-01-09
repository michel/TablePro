#!/bin/bash
# Create a professional DMG background image

set -e

OUTPUT_DIR="${1:-.dmg-assets}"
OUTPUT_FILE="$OUTPUT_DIR/dmg-background.png"

mkdir -p "$OUTPUT_DIR"

echo "🎨 Creating DMG background image..."

# Check for ImageMagick (v7 uses 'magick', v6 uses 'convert')
MAGICK_CMD=""
if command -v magick &> /dev/null; then
    MAGICK_CMD="magick"
elif command -v convert &> /dev/null; then
    MAGICK_CMD="convert"
else
    echo "❌ ERROR: ImageMagick not found"
    echo "   Install with: brew install imagemagick"
    exit 1
fi

# DMG window size: 600x400
WIDTH=600
HEIGHT=400

# Create background with gradient
$MAGICK_CMD -size ${WIDTH}x${HEIGHT} \
    gradient:'#f5f5f7-#ffffff' \
    "$OUTPUT_FILE"

# Add arrow pointing from left to right
$MAGICK_CMD "$OUTPUT_FILE" \
    -stroke '#007AFF' \
    -strokewidth 3 \
    -fill none \
    -draw "path 'M 250,200 L 350,200'" \
    -draw "path 'M 340,190 L 350,200 L 340,210'" \
    "$OUTPUT_FILE"

# Add subtle text hint at bottom
$MAGICK_CMD "$OUTPUT_FILE" \
    -font "Helvetica" \
    -pointsize 13 \
    -fill '#86868b' \
    -gravity South \
    -annotate +0+30 'Drag the app icon to the Applications folder to install' \
    "$OUTPUT_FILE"

# Add subtle shadow effect
$MAGICK_CMD "$OUTPUT_FILE" \
    \( +clone -background black -shadow 60x3+0+0 \) \
    +swap -background none -layers merge +repage \
    "$OUTPUT_FILE"

echo "✅ Background image created: $OUTPUT_FILE"
echo "   Size: ${WIDTH}x${HEIGHT}"
