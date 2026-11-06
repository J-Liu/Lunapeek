#!/bin/bash
# Download official libmpv.xcframework from media-kit releases

set -e

OUTPUT_DIR="Lunapeek/Frameworks"
TMP_DIR="tmp-libmpv-download"

echo "========================================"
echo "Downloading libmpv.xcframework"
echo "Source: media-kit/libmpv-darwin-build"
echo "========================================"

# Get latest release info
echo "Fetching latest release info..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/media-kit/libmpv-darwin-build/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE" ]; then
    echo "ERROR: Failed to get latest release version"
    exit 1
fi

echo "Latest version: $LATEST_RELEASE"

# Download URL (video version for VideoToolbox hardware decoding)
DOWNLOAD_URL="https://github.com/media-kit/libmpv-darwin-build/releases/download/${LATEST_RELEASE}/libmpv-xcframeworks_${LATEST_RELEASE}_ios-universal-video-default.tar.gz"

echo "Download URL: $DOWNLOAD_URL"

# Create tmp directory
mkdir -p "$TMP_DIR"

# Download
echo ""
echo "Downloading..."
curl -L -o "$TMP_DIR/libmpv.tar.gz" "$DOWNLOAD_URL"

# Extract
echo ""
echo "Extracting..."
cd "$TMP_DIR"
tar -xzf libmpv.tar.gz

# Find extracted directory name
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "libmpv-xcframeworks_*" | head -n1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "ERROR: xcframeworks directory not found in downloaded archive"
    exit 1
fi

echo "Found: $EXTRACTED_DIR"

# Verify Mpv.xcframework exists
if [ ! -d "$EXTRACTED_DIR/Mpv.xcframework" ]; then
    echo "ERROR: Mpv.xcframework not found"
    exit 1
fi

# Copy all xcframeworks to output directory
cd ..
mkdir -p "$OUTPUT_DIR"
cp -r "$TMP_DIR/$EXTRACTED_DIR/"*.xcframework "$OUTPUT_DIR/"

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "========================================"
echo "Download completed!"
echo "========================================"
echo ""
echo "All xcframeworks saved to: $OUTPUT_DIR/"
echo "Version: $LATEST_RELEASE"
echo ""
echo "Included frameworks:"
echo "  - Mpv.xcframework (libmpv)"
echo "  - Avcodec, Avformat, Avutil (FFmpeg)"
echo "  - Swresample, Swscale (audio/video processing)"
echo "  - Dav1d (AV1 decoder)"
echo "  - Ass, Freetype, Fribidi, Harfbuzz (subtitles)"
echo ""
echo "Source: https://github.com/media-kit/libmpv-darwin-build"
echo ""
echo "To use in Xcode:"
echo "  1. Add all .xcframework files to project"
echo "  2. Set 'Embed & Sign' for Mpv.xcframework"
echo "  3. Add '-ObjC' to Other Linker Flags"
echo ""
echo "Next steps:"
echo "  - Create Swift wrapper for libmpv C API"
echo "  - Implement async seek using mpv_command()"
echo "  - Enable VideoToolbox: hwdec=auto"
