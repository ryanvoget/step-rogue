#!/bin/bash
# Run this on your MacBook after pulling from GitHub.
# Output: bin/HealthKitBridge.xcframework  (commit bin/ back to git when done)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
OUTPUT_DIR="$SCRIPT_DIR/bin"
FW_NAME="HealthKitBridge"

echo "==> Building $FW_NAME for iOS arm64..."
swift build \
    -c release \
    --triple arm64-apple-ios17.0 \
    --package-path "$SCRIPT_DIR"

DYLIB="$BUILD_DIR/arm64-apple-ios17.0/release/lib${FW_NAME}.dylib"
if [ ! -f "$DYLIB" ]; then
    echo "ERROR: library not found at $DYLIB"
    exit 1
fi

echo "==> Packaging as .framework..."
FW_DIR="$BUILD_DIR/${FW_NAME}.framework"
rm -rf "$FW_DIR"
mkdir -p "$FW_DIR"
cp "$DYLIB" "$FW_DIR/$FW_NAME"
install_name_tool -id "@rpath/${FW_NAME}.framework/${FW_NAME}" "$FW_DIR/$FW_NAME"

cat > "$FW_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${FW_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.parsec.healthkitbridge</string>
    <key>CFBundleName</key><string>${FW_NAME}</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>16.0</string>
</dict>
</plist>
PLIST

echo "==> Creating xcframework..."
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/${FW_NAME}.xcframework"
xcodebuild -create-xcframework \
    -framework "$FW_DIR" \
    -output "$OUTPUT_DIR/${FW_NAME}.xcframework"

echo ""
echo "Done: $OUTPUT_DIR/${FW_NAME}.xcframework"
echo ""
echo "Next steps:"
echo "  git add addons/healthkit_bridge/bin/"
echo "  git commit -m 'Add HealthKit GDExtension binary'"
echo "  git push"
