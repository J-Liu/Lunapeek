#!/bin/bash

xcodebuild -project AmbulAR.xcodeproj \
  -scheme AmbulAR \
  -destination 'platform=iOS,name=iPhone' \
  -allowProvisioningUpdates \
  build
