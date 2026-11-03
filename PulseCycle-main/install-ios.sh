#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright © 2026 Jia Liu
#
# Install script for iOS target.
# Usage: ./install-ios.sh

set -e

./build-ios.sh

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/PulseCycle-*/Build/Products/Debug-iphoneos/PulseCycle.app -maxdepth 0 2>/dev/null)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find PulseCycle.app"
    exit 1
fi

echo "==> Installing: $APP_PATH"
xcrun devicectl device install app --device iPhone "$APP_PATH"

echo "==> Install complete"
