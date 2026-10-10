#!/bin/bash

# Build both main app and widget extension
xcodebuild -project Lunapeek.xcodeproj \
  -scheme Lunapeek \
  -destination 'platform=iOS,name=iPhone' \
  -allowProvisioningUpdates \
  build

xcodebuild -project Lunapeek.xcodeproj \
  -scheme LunapeekWidgetExtension \
  -destination 'platform=iOS,name=iPhone' \
  -allowProvisioningUpdates \
  build
