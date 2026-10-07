#!/bin/bash

xcodebuild -project Lunapeek.xcodeproj \
  -scheme Lunapeek \
  -destination 'platform=iOS,name=iPhone' \
  -allowProvisioningUpdates \
  build
