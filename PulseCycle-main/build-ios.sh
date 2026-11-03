#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright © 2026 Jia Liu
#
# Build script for iOS target.
# Usage: ./build-ios.sh

set -e

echo "==> Building PulseCycle for iOS..."
xcodebuild -project PulseCycle.xcodeproj \
  -scheme PulseCycle \
  -destination 'platform=iOS,name=iPhone' \
  -allowProvisioningUpdates \
  build

echo "==> Build complete"
