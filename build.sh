#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_KIT_DIR="ffmpeg-kit"
RELEASE_TAG="v6.0"

cd "$SCRIPT_DIR"

# Clone or checkout ffmpeg-kit-next
if [ ! -d "$FFMPEG_KIT_DIR" ]; then
    echo "Cloning ffmpeg-kit-next with tag $RELEASE_TAG..."
    git clone --branch "$RELEASE_TAG" --depth 1 https://github.com/arthenica/ffmpeg-kit.git "$FFMPEG_KIT_DIR"
else
    echo "ffmpeg-kit-next directory exists, checking tag..."
    cd "$FFMPEG_KIT_DIR"

    # Fetch tags if needed
    git fetch --tags --depth 1 origin "$RELEASE_TAG" 2>/dev/null || true

    # Checkout to the release tag
    if git rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
        git checkout "$RELEASE_TAG"
    else
        echo "Tag $RELEASE_TAG not found, re-cloning..."
        cd "$SCRIPT_DIR"
        rm -rf "$FFMPEG_KIT_DIR"
        git clone --branch "$RELEASE_TAG" --depth 1 https://github.com/arthenica/ffmpeg-kit.git "$FFMPEG_KIT_DIR"
    fi
    cd "$SCRIPT_DIR"
fi

cd "$FFMPEG_KIT_DIR"

# Build iOS framework with SPM support
echo "Building FFmpeg for iOS..."
echo "Options: xcframework, SPM, VideoToolbox, AudioToolbox, AVFoundation"
echo "NOT enabling GPL libraries"

./ios.sh \
    -x \
    --spm \
    --enable-lib-ios-videotoolbox \
    --enable-lib-ios-audiotoolbox \
    --enable-lib-ios-avfoundation

# Print output location
PRODUCT_PATH="$SCRIPT_DIR/$FFMPEG_KIT_DIR/prebuilt/bundle-apple-xcframework-ios"
if [ -d "$PRODUCT_PATH" ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo "Product path: $PRODUCT_PATH"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi