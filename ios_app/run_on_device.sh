#!/bin/bash
# Workaround for Xcode 26 IDEInstallCoreDeviceWorker 3002 bug.
# Run this AFTER building in Xcode (⌘B). Installs + launches with live console.

DEVICE="7E1A516A-2545-5271-9CE8-A8ED2B7ED70C"
APP="/Users/valeria/Library/Developer/Xcode/DerivedData/ParsecApp-eeqyfrkhkqljgigcsuhnvcrjuunf/Build/Products/Debug-iphoneos/ParsecApp.app"
BUNDLE="com.parsec.game"

set -e
echo "Installing..."
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Launching with console..."
xcrun devicectl device process launch --device "$DEVICE" --console "$BUNDLE"
