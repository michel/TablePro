# DMG Installer Creation

This document explains how to create professional DMG installers for TablePro.

## Quick Start

```bash
# Build the app first
./build-release.sh arm64

# Create DMG
./create-dmg.sh 0.1.13 arm64 build/Release/TablePro-arm64.app

# Test it
open build/Release/TablePro-0.1.13-arm64.dmg
```

## Features

✅ Professional drag-and-drop installation window
✅ Applications folder symlink for easy installation
✅ Custom background with visual arrow
✅ Compressed format for smaller downloads
✅ No Apple Developer account required

## Troubleshooting

### Applications Folder Icon Not Showing

If the Applications folder appears as just text without an icon:

**Why this happens:**
- macOS caches folder icons and sometimes doesn't immediately recognize symlinks
- This is a known macOS behavior, not a bug in the DMG

**Solutions:**

1. **Eject and re-mount** (Most reliable):
   ```bash
   # Eject the DMG
   hdiutil detach "/Volumes/TablePro 0.1.13"

   # Re-open it
   open build/Release/TablePro-0.1.13-arm64.dmg
   ```
   The icon should appear correctly after re-mounting.

2. **Clear icon cache** (If problem persists):
   ```bash
   sudo rm -rf /Library/Caches/com.apple.iconservices.store
   sudo find /private/var/folders/ -name com.apple.iconservices -exec rm -rf {} \;
   killall Finder
   ```

3. **Force refresh**:
   - Open the DMG
   - Press `Cmd + Option + Esc`
   - Force quit Finder
   - Re-open the DMG

### Background Image Not Showing

If you see a plain gray background instead of the custom image:

**Requirements:**
- ImageMagick must be installed: `brew install imagemagick`

**Check if installed:**
```bash
which magick  # Should return: /opt/homebrew/bin/magick (or similar)
```

**Without ImageMagick:**
The DMG will still work perfectly fine, just without the custom background image.

## Advanced Usage

### Custom Background

Create your own background image:

```bash
./create-dmg-background.sh [output-directory]
```

This creates a 600x400 PNG image with:
- Gradient background
- Blue arrow pointing right
- Installation instruction text

### Manual DMG Configuration

The script automatically:
1. Creates a staging directory
2. Copies the app bundle
3. Creates Applications symlink
4. Generates background image
5. Sets Finder view options via AppleScript
6. Compresses to final DMG

All settings can be modified in `create-dmg.sh`.

## CI/CD Integration

The GitHub Actions workflow automatically creates DMG files:

1. Builds app for both ARM64 and x86_64
2. Creates DMG for each architecture
3. Uploads as artifacts
4. Includes in GitHub releases

See `.github/workflows/build.yml` for details.

## Best Practices

### For Distribution

1. **Always test the DMG** on a clean Mac before distributing
2. **Eject and re-mount** to verify icons appear correctly
3. **Test installation** by dragging to Applications
4. **Check first launch** behavior (right-click → Open for unsigned apps)

### File Naming

The script uses this format:
```
TablePro-{version}-{architecture}.dmg
```

Examples:
- `TablePro-0.1.13-arm64.dmg` (Apple Silicon)
- `TablePro-0.1.13-x86_64.dmg` (Intel)

### Size Optimization

DMG files are compressed with maximum compression:
- Format: UDZO (compressed, read-only)
- Compression: zlib level 9
- Typical size: ~1-2 MB (depending on app size)

## Technical Details

### DMG Creation Process

1. **Staging**:
   - Creates temporary directory structure
   - Copies app and creates symlink
   - Generates background image

2. **Temporary DMG**:
   - Creates writable DMG with `hdiutil create`
   - Mounts with read-write permissions

3. **Configuration**:
   - Runs AppleScript to set Finder view options
   - Positions icons at specific coordinates
   - Sets background image

4. **Finalization**:
   - Ensures .DS_Store is written
   - Unmounts temporary DMG
   - Converts to compressed read-only format

### AppleScript Settings

The script configures:
- Window size: 600x400 pixels
- Icon view mode
- Icon size: 72 pixels
- No toolbar or status bar
- Custom background image
- Specific icon positions

## Compatibility

- **macOS Version**: 10.13+ (High Sierra and later)
- **Architecture**: ARM64 (Apple Silicon) and x86_64 (Intel)
- **Tools Required**:
  - `hdiutil` (built into macOS)
  - `osascript` (built into macOS)
  - `imagemagick` (optional, for custom backgrounds)

## License

These scripts are part of the TablePro project and follow the same license.
