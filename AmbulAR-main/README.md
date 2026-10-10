# AmbulAR

A native iOS AR distance tracking app using ARKit and CoreMotion.

## Features

- **ARKit-based Distance Tracking**: Uses visual inertial odometry to calculate horizontal distance traveled
- **CoreMotion Auxiliary Support**: CMPedometer integration for motion detection and fallback when AR tracking is limited
- **Real-time AR Anchors**: Visual markers placed at key points (start, pause, resume, finish) in augmented reality
- **Tracking Quality Monitoring**: Automatic detection and user feedback for tracking quality issues
- **Unit Conversion**: Display distance in meters, kilometers, feet, or miles
- **Multi-language Support**: English, Simplified Chinese, and Traditional Chinese with in-app switching
- **Hand Preference**: Configurable finish button position for left-handed or right-handed users
- **Pure UIKit Implementation**: No SwiftUI or Storyboards, fully programmatic UI

## Requirements

- iOS 18.0 or later
- Xcode 16.0 or later
- ARKit compatible device (iOS device with A9 chip or later)

## Architecture

- **Logic/UI Separation**: Distance calculation and state management are independent of view controllers
- **Sensor Fusion**: ARKit and CoreMotion data are intelligently fused for accuracy
- **State Machine**: Clear tracking flow with idle → tracking → paused → finished states
- **Horizontal Displacement**: Only accumulates X/Z axis movement, ignoring vertical changes

## Project Structure

```
AmbulAR/
├── AppDelegate.swift           # Application lifecycle
├── SceneDelegate.swift         # Scene lifecycle (iOS 13+)
├── ARSessionViewController.swift # Main AR view controller
├── ResultViewController.swift  # Result display screen
├── SessionController.swift     # State machine and coordination
├── DistanceTracker.swift       # Pure ARKit distance calculation
├── MotionMonitor.swift         # CMPedometer wrapper
├── SensorFusion.swift          # ARKit + CoreMotion fusion
├── TrackingState.swift         # Tracking state enum
├── TrackingQualityMonitor.swift # AR tracking quality monitor
├── AnchorManager.swift         # AR anchor management
├── MarkerView.swift            # Visual marker component
├── MarkerType.swift            # Marker type definitions
└── DistanceUnit.swift          # Unit conversion utilities
```

## Usage

1. Launch the app and grant camera and motion permissions
2. Point the camera at your surroundings
3. Tap "Start" to begin tracking your movement
4. Walk around while the app tracks your horizontal distance
5. Tap "Pause" to temporarily stop tracking
6. Tap "Continue" to resume from your current position
7. Tap "Finish" to complete the session and view your total distance

## Settings

Access settings via the gear icon in the top-right corner:

- **Language**: Choose between System Default, English, Simplified Chinese, or Traditional Chinese
- **Display Unit**: Meters, Kilometers, Feet, or Miles
- **Hand Preference**: Right-handed (Finish button on right) or Left-handed (Finish button on left)

## Privacy

AmbulAR requires the following permissions:

- **Camera**: Used for ARKit visual tracking to determine your position in 3D space
- **Motion & Fitness**: Used to detect walking/running and provide fallback distance estimation

## License

This project is licensed under the **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**, with an **additional permission under Section 7** allowing distribution through app stores under certain conditions.

See [LICENSE](LICENSE) for the full license text and the exact wording of the additional permission.

## Attribution

AmbulAR - A native iOS AR distance tracker using camera and ARKit
Copyright 2026 Jia Liu

This product includes software developed by Jia Liu.

The original AmbulAR project and its contributors must be credited in any redistribution or derivative work. This attribution notice must be retained in all copies or substantial portions of the software.

See [NOTICE](NOTICE) for details.
