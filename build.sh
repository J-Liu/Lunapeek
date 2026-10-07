#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_KIT_DIR="ffmpeg-kit"
RELEASE_TAG="v6.0"

cd "$SCRIPT_DIR"

# Clone or checkout ffmpeg-kit if not exists
if [ ! -d "$FFMPEG_KIT_DIR" ]; then
    echo "Cloning ffmpeg-kit with tag $RELEASE_TAG..."
    git clone --branch "$RELEASE_TAG" --depth 1 https://github.com/arthenica/ffmpeg-kit.git "$FFMPEG_KIT_DIR"
else
    echo "ffmpeg-kit directory exists, skipping clone"
    cd "$FFMPEG_KIT_DIR"

    # Check if we're on the correct tag
    CURRENT_TAG=$(git describe --tags 2>/dev/null || echo "unknown")
    if [ "$CURRENT_TAG" != "$RELEASE_TAG" ]; then
        echo "Current tag is $CURRENT_TAG, checking out $RELEASE_TAG..."
        git fetch --tags --depth 1 origin "$RELEASE_TAG" 2>/dev/null || true
        git checkout "$RELEASE_TAG" 2>/dev/null || {
            echo "Tag $RELEASE_TAG not found locally, fetching..."
            git fetch --depth 1 origin tag "$RELEASE_TAG"
            git checkout "$RELEASE_TAG"
        }
    fi
    cd "$SCRIPT_DIR"
fi

cd "$FFMPEG_KIT_DIR"

# Build iOS xcframework with hardware acceleration
echo "Building FFmpeg for iOS..."
echo "Options: xcframework, VideoToolbox, AudioToolbox, AVFoundation"
echo "NOT enabling GPL libraries"

./ios.sh \
    -x \
    --enable-ios-videotoolbox \
    --enable-ios-audiotoolbox \
    --enable-ios-avfoundation

# Print output location
PRODUCT_PATH="$SCRIPT_DIR/$FFMPEG_KIT_DIR/prebuilt/bundle-apple-xcframework-ios"
if [ -d "$PRODUCT_PATH" ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo "Product path: $PRODUCT_PATH"
    echo ""
    echo "Generated xcframeworks:"
    ls -1 "$PRODUCT_PATH"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi
