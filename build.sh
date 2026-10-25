#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright 2026 Jia Liu

# Build main app
xcodebuild -project Lunapeek.xcodeproj \
  -scheme Lunapeek \
  -destination 'platform=iOS,name=iPhone' \
  -allowProvisioningUpdates \
  build
