#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_KIT_DIR="ffmpeg-kit-next-9.0.0"
VERSION="9.0.0"
TARBALL_URL="https://github.com/arthenica/ffmpeg-kit-next/archive/refs/tags/v${VERSION}.tar.gz"
CACHE_DIR="$SCRIPT_DIR/.cache"

cd "$SCRIPT_DIR"

# Check Nix installation
if ! command -v nix &> /dev/null; then
    echo "ERROR: Nix not found"
    echo "Install with: curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh"
    exit 1
fi

# Source Nix daemon profile
if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Create cache directory
mkdir -p "$CACHE_DIR"

# Download and extract tarball (reuse if exists)
TARBALL_PATH="$CACHE_DIR/ffmpeg-kit-next-${VERSION}.tar.gz"

if [ ! -d "$FFMPEG_KIT_DIR" ]; then
    if [ ! -f "$TARBALL_PATH" ]; then
        echo "Downloading ffmpeg-kit-next v${VERSION} tarball..."
        curl -L -o "$TARBALL_PATH" "$TARBALL_URL"
    else
        echo "✓ Using cached tarball"
    fi

    echo "Extracting..."
    tar -xzf "$TARBALL_PATH" -C "$CACHE_DIR"
    mv "$CACHE_DIR/ffmpeg-kit-next-${VERSION}" "$FFMPEG_KIT_DIR"
else
    echo "✓ $FFMPEG_KIT_DIR directory exists, skipping download"
fi

cd "$FFMPEG_KIT_DIR"

# Build iOS xcframework
echo ""
echo "Building FFmpeg for iOS..."
echo "Version: ${VERSION}"
echo "Features: VideoToolbox, AudioToolbox, AVFoundation, dav1d, libvpx, opus"
echo ""

./nix-ios.sh \
    -p xcode26 \
    -x \
    --enable-lib-ios-videotoolbox \
    --enable-lib-ios-audiotoolbox \
    --enable-lib-ios-avfoundation \
    --enable-lib-dav1d \
    --enable-lib-libvpx \
    --enable-lib-opus

# Print output location
PRODUCT_PATH="$SCRIPT_DIR/$FFMPEG_KIT_DIR/prebuilt/bundle-apple-xcframework-ios-12.1"
if [ -d "$PRODUCT_PATH" ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo "Product path: $PRODUCT_PATH"
    echo ""
    echo "Generated xcrameworks:"
    ls -1 "$PRODUCT_PATH"
    echo ""
    echo "License: LGPL 3.0"
else
    echo ""
    echo "❌ Build failed. Check build.log for details."
    echo "Log: $SCRIPT_DIR/$FFMPEG_KIT_DIR/build.log"
    exit 1
fi
