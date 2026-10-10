#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright 2026 Jia Liu

# Build both targets first
./build.sh

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Lunapeek-*/Build/Products/Debug-iphoneos/Lunapeek.app -maxdepth 0 2>/dev/null)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find Lunapeek.app"
    exit 1
fi

echo "Installing: $APP_PATH"
xcrun devicectl device install app --device iPhone "$APP_PATH"
