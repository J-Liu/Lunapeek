#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_KIT_DIR="ffmpeg-kit"
RELEASE_TAG="v6.0"

cd "$SCRIPT_DIR"

# Check dependencies
echo "Checking dependencies..."
if ! command -v pkg-config &> /dev/null; then
    echo "Installing pkg-config..."
    brew install pkg-config
fi

# Install zlib for pkg-config
if ! brew list zlib &> /dev/null 2>&1; then
    echo "Installing zlib..."
    brew install zlib
fi

# Clone ffmpeg-kit if not exists
if [ ! -d "$FFMPEG_KIT_DIR" ]; then
    echo "Cloning ffmpeg-kit with tag $RELEASE_TAG..."
    git clone --branch "$RELEASE_TAG" --depth 1 https://github.com/arthenica/ffmpeg-kit.git "$FFMPEG_KIT_DIR"
else
    echo "ffmpeg-kit directory exists, checking version..."
    cd "$FFMPEG_KIT_DIR"
    CURRENT_TAG=$(git describe --tags 2>/dev/null || echo "unknown")
    if [ "$CURRENT_TAG" != "$RELEASE_TAG" ]; then
        echo "Updating to $RELEASE_TAG..."
        git fetch --tags --depth 1 origin "$RELEASE_TAG" || true
        git checkout "$RELEASE_TAG" || true
    fi
    cd "$SCRIPT_DIR"
fi

cd "$FFMPEG_KIT_DIR"

# Build iOS xcframework with full package (LGPL)
# Includes: dav1d, fontconfig, freetype, fribidi, gmp, gnutls, kvazaar, lame,
#           libass, libiconv, libilbc, libtheora, libvorbis, libvpx, libwebp,
#           libxml2, opencore-amr, opus, shine, snappy, soxr, speex, twolame,
#           vo-amrwbenc, zimg
echo ""
echo "Building FFmpeg for iOS..."
echo "Package: full (LGPL 3.0)"
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
