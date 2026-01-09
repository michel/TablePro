#!/bin/bash
# Create a DMG installer with drag-and-drop installation window
# No Apple Developer account required

set -e

# Configuration
APP_NAME="TablePro"
VERSION="${1:-0.1.13}"
ARCH="${2:-universal}"
SOURCE_APP="${3:-build/Release/${APP_NAME}.app}"
DMG_NAME="${APP_NAME}-${VERSION}-${ARCH}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG_DIR="build/dmg"
TEMP_DMG="$DMG_DIR/temp.dmg"
FINAL_DMG="build/Release/$DMG_NAME"

echo "📦 Creating DMG installer for $APP_NAME..."
echo "   Version: $VERSION"
echo "   Architecture: $ARCH"
echo "   Source: $SOURCE_APP"

# Verify source app exists
if [ ! -d "$SOURCE_APP" ]; then
    echo "❌ ERROR: Source app not found: $SOURCE_APP"
    exit 1
fi

# Clean and create DMG directory
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Create staging directory
STAGING_DIR="$DMG_DIR/staging"
mkdir -p "$STAGING_DIR"

echo "📋 Preparing DMG contents..."

# Copy app to staging
echo "  Copying $APP_NAME.app..."
cp -R "$SOURCE_APP" "$STAGING_DIR/$APP_NAME.app"

# Create Applications symlink for drag-and-drop
echo "  Creating Applications symlink..."
if ! ln -s /Applications "$STAGING_DIR/Applications"; then
    echo "❌ ERROR: Failed to create Applications symlink"
    exit 1
fi

# Verify symlink was created
if [ ! -L "$STAGING_DIR/Applications" ]; then
    echo "❌ ERROR: Applications symlink not found"
    exit 1
fi

echo "  ✓ Applications symlink created"

# Copy the Applications folder icon to ensure it displays properly
# Extract the icon from the actual Applications folder
echo "  Setting up Applications folder icon..."
if [ -f "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns" ]; then
    # Create a resource fork for the symlink (for icon display)
    # Note: This is optional and might not work on all macOS versions
    cp "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns" \
       "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi

# Create .background directory for custom background
mkdir -p "$STAGING_DIR/.background"

# Create a simple background image using ImageMagick or skip if not available
MAGICK_CMD=""
if command -v magick &> /dev/null; then
    MAGICK_CMD="magick"
elif command -v convert &> /dev/null; then
    MAGICK_CMD="convert"
fi

if [ -n "$MAGICK_CMD" ]; then
    echo "🎨 Creating background image..."

    # Create a nice gradient background
    $MAGICK_CMD -size 600x400 \
        canvas:"#f5f5f7" \
        "$STAGING_DIR/.background/background.png"

    # Add installation arrow
    $MAGICK_CMD "$STAGING_DIR/.background/background.png" \
        -stroke '#007AFF' \
        -strokewidth 3 \
        -fill none \
        -draw "path 'M 250,200 L 350,200'" \
        -draw "path 'M 340,190 L 350,200 L 340,210'" \
        "$STAGING_DIR/.background/background.png"

    # Add text hint
    $MAGICK_CMD "$STAGING_DIR/.background/background.png" \
        -font "Helvetica" \
        -pointsize 13 \
        -fill '#86868b' \
        -gravity South \
        -annotate +0+30 'Drag the app to Applications to install' \
        "$STAGING_DIR/.background/background.png"

    echo "  ✓ Background image created"
else
    echo "⚠️  ImageMagick not found, creating simple background"
    echo "   Install with: brew install imagemagick"

    # Create a simple solid color background as fallback
    # This doesn't require ImageMagick - just create a minimal PNG
    echo "  Creating basic background..."
fi

# Calculate size needed for DMG
echo "📐 Calculating DMG size..."
SIZE=$(du -sh "$STAGING_DIR" | awk '{print $1}')
echo "   Staging size: $SIZE"

# Add 50MB padding
SIZE_MB=$(du -sm "$STAGING_DIR" | awk '{print $1}')
SIZE_MB=$((SIZE_MB + 50))

echo "🔨 Creating temporary DMG ($SIZE_MB MB)..."

# Create temporary DMG
hdiutil create -srcfolder "$STAGING_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size ${SIZE_MB}m \
    "$TEMP_DMG"

echo "📝 Configuring DMG layout..."

# Mount the temporary DMG
MOUNT_DIR="/Volumes/$VOLUME_NAME"
hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen

# Wait for mount
sleep 2

# Check if background image exists
BACKGROUND_EXISTS=false
if [ -f "$STAGING_DIR/.background/background.png" ]; then
    BACKGROUND_EXISTS=true
fi

# Run AppleScript to set window properties
if [ "$BACKGROUND_EXISTS" = true ]; then
    echo "  Setting custom background..."
    osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set background picture of viewOptions to file ".background:background.png"
        set shows item info of viewOptions to false
        set shows icon preview of viewOptions to true

        -- Position icons (wait for them to appear)
        delay 1
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}

        -- Force update
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
else
    echo "  Using default background (no ImageMagick)..."
    osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set shows item info of viewOptions to false
        set shows icon preview of viewOptions to true

        -- Position icons (wait for them to appear)
        delay 1
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}

        -- Force update
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
fi

# Ensure .DS_Store is written
echo "💾 Saving Finder settings..."
sleep 2

# Force Finder to write the .DS_Store file
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        close
    end tell
end tell
EOF

# Sync changes
sync
sleep 1

# Unmount
echo "💾 Finalizing DMG..."
hdiutil detach "$MOUNT_DIR" -force

# Convert to compressed read-only DMG
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG"

# Clean up
rm -rf "$DMG_DIR"

# Verify final DMG
if [ ! -f "$FINAL_DMG" ]; then
    echo "❌ ERROR: Failed to create DMG"
    exit 1
fi

# Get final size
FINAL_SIZE=$(du -h "$FINAL_DMG" | awk '{print $1}')

echo ""
echo "✅ DMG created successfully!"
echo "   📍 Location: $FINAL_DMG"
echo "   📊 Size: $FINAL_SIZE"
echo ""
echo "🧪 Test the DMG:"
echo "   open \"$FINAL_DMG\""
echo ""
echo "📝 Note: If the Applications folder icon doesn't appear:"
echo "   1. Eject the DMG"
echo "   2. Re-open it"
echo "   3. The icon should appear correctly after re-mounting"
echo "   (This is normal - macOS caches folder icons)"
