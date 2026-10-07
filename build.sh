#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_KIT_DIR="ffmpeg-kit-next"
VERSION="9.0.0"
TARBALL_URL="https://github.com/arthenica/ffmpeg-kit-next/archive/refs/tags/v${VERSION}.tar.gz"
CACHE_DIR="$SCRIPT_DIR/.cache"

cd "$SCRIPT_DIR"

# Check dependencies
echo "Checking dependencies..."
if ! command -v pkg-config &> /dev/null; then
    echo "Installing pkg-config..."
    brew install pkg-config
fi

if ! brew list zlib &> /dev/null 2>&1; then
    echo "Installing zlib..."
    brew install zlib
fi

# Create cache directory
mkdir -p "$CACHE_DIR"

# Download and extract tarball
if [ ! -d "$FFMPEG_KIT_DIR" ]; then
    TARBALL_PATH="$CACHE_DIR/ffmpeg-kit-next-${VERSION}.tar.gz"

    if [ ! -f "$TARBALL_PATH" ]; then
        echo "Downloading ffmpeg-kit-next v${VERSION} tarball..."
        curl -L -o "$TARBALL_PATH" "$TARBALL_URL"
    else
        echo "Using cached tarball: $TARBALL_PATH"
    fi

    echo "Extracting..."
    tar -xzf "$TARBALL_PATH" -C "$CACHE_DIR"
    mv "$CACHE_DIR/ffmpeg-kit-next-${VERSION}" "$FFMPEG_KIT_DIR"
else
    echo "ffmpeg-kit-next directory exists, skipping download"
fi

cd "$FFMPEG_KIT_DIR"

# Set GNU sed path
if command -v gsed &> /dev/null; then
    export SED=$(which gsed)
elif [ -x "/opt/homebrew/opt/gnu-sed/libexec/gnubin/sed" ]; then
    export SED="/opt/homebrew/opt/gnu-sed/libexec/gnubin/sed"
elif [ -x "/usr/local/opt/gnu-sed/libexec/gnubin/sed" ]; then
    export SED="/usr/local/opt/gnu-sed/libexec/gnubin/sed"
else
    echo "ERROR: GNU sed not found"
    echo "Install with: brew install gnu-sed"
    exit 1
fi

echo "Using GNU sed: $SED"

# Build iOS xcframework with full package (LGPL)
echo ""
echo "Building FFmpeg for iOS..."
echo "Package: full (LGPL 3.0)"
echo "Version: ${VERSION}"
echo "Features: VideoToolbox, AudioToolbox, AVFoundation, network support"
echo ""

./ios.sh \
    -x \
    --enable-ios-videotoolbox \
    --enable-ios-audiotoolbox \
    --enable-ios-avfoundation \
    --full

# Print output location
PRODUCT_PATH="$SCRIPT_DIR/$FFMPEG_KIT_DIR/prebuilt/bundle-apple-xcframework-ios"
if [ -d "$PRODUCT_PATH" ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo "Product path: $PRODUCT_PATH"
    echo ""
    echo "Generated xcframeworks:"
    ls -1 "$PRODUCT_PATH"
    echo ""
    echo "License: LGPL 3.0"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi
