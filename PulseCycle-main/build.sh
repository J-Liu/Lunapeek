#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright © 2026 Jia Liu
#
# Builds the release executables and assembles a signed PulseCycle.app bundle.
# Usage: ./build.sh

set -euo pipefail

APP_NAME="PulseCycle"
GUI_NAME="PulseCycleMacGUI"
BUILD_CONFIG="release"

# Resolve project root (script is in root)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# 1. Build the binaries
echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
swift build -c "$BUILD_CONFIG"

BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
GUI_BINARY="${BIN_DIR}/${GUI_NAME}"

if [ ! -f "$GUI_BINARY" ]; then
    echo "Error: GUI binary not found at ${GUI_BINARY}"
    exit 1
fi

# 2. Assemble .app bundle structure (in root directory)
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
echo "==> Assembling ${APP_BUNDLE}..."

rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"

# Copy executable
cp "$GUI_BINARY" "${APP_BUNDLE}/Contents/MacOS/${GUI_NAME}"

# Copy Info.plist from Resources/
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy pre-compiled icon assets (committed to git)
ICON_DIR="${ROOT_DIR}/Resources/Compiled"
if [ -f "${ICON_DIR}/Assets.car" ]; then
    cp "${ICON_DIR}/Assets.car" "${APP_BUNDLE}/Contents/Resources/Assets.car"
fi
if [ -f "${ICON_DIR}/${APP_NAME}.icns" ]; then
    cp "${ICON_DIR}/${APP_NAME}.icns" "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"
fi

# Copy audio files from iOS resources
AUDIO_DIR="${ROOT_DIR}/PulseCycle"
for audio in boxing-bell-1.wav boxing-bell-2.wav boxing-bell-3.wav countdown_beep.wav; do
    if [ -f "${AUDIO_DIR}/${audio}" ]; then
        cp "${AUDIO_DIR}/${audio}" "${APP_BUNDLE}/Contents/Resources/"
    fi
done

# Copy Sparkle.framework
SPARKLE_BUILD_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
SPARKLE_FRAMEWORK="${SPARKLE_BUILD_DIR}/../../release/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    # Try alternate path
    SPARKLE_FRAMEWORK="${ROOT_DIR}/.build/release/Sparkle.framework"
fi
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "==> Copying Sparkle.framework..."
    cp -a "$SPARKLE_FRAMEWORK" "${APP_BUNDLE}/Contents/Frameworks/"
fi

# Add rpath for frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP_BUNDLE}/Contents/MacOS/${GUI_NAME}" 2>/dev/null || true

# 3. Sign with local certificate (stable identity for TCC)
echo "==> Signing..."
if security find-identity -v -p codesigning | grep -q "Local Development Signing"; then
    codesign --force --deep --sign "Local Development Signing" "$APP_BUNDLE"
    echo "==> Signed ${APP_BUNDLE} using certificate"
else
    # Fallback to ad-hoc signing
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "==> Signed ${APP_BUNDLE} by ad-hoc"
fi

echo ""
echo "==> Done: ${APP_BUNDLE}"
echo "    Run: open \"${APP_BUNDLE}\""
