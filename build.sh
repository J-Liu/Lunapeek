#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "FFmpeg-kit integration instructions:"
echo ""
echo "1. Using CocoaPods (recommended):"
echo "   Add to Podfile:"
echo "   pod 'ffmpeg-kit-ios-min', '~> 6.0'"
echo ""
echo "2. Using Swift Package Manager:"
echo "   Add package: https://github.com/arthenica/ffmpeg-kit"
echo "   Select product: FFmpegKit"
echo ""
echo "3. Manual integration:"
echo "   Download from: https://github.com/arthenica/ffmpeg-kit/releases/tag/v6.0"
echo "   Add ffmpegkit.xcframework to Xcode project"
echo ""
echo "For this project, we'll skip FFmpeg for now and rely on system frameworks."
echo "FFmpeg can be integrated later when needed for additional formats."
