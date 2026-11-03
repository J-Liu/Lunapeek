# PulseCycle

A HIIT (High-Intensity Interval Training) interval timer with real-time heart rate monitoring for iOS and macOS.

## Features

- **Interval Timer**: Configurable warm-up, work, rest, and cool-down phases
- **Heart Rate Monitoring**: Real-time heart rate display via Bluetooth LE chest straps
- **Profile System**: Save and switch between multiple workout configurations
- **Customizable Settings**:
  - Rounds, work/rest duration, warning timing
  - Start/end/warning sounds
  - Color themes for different phases
  - Voice announcements

## Platforms

- **iOS**: Requires iOS 15+ (Xcode project)
- **macOS**: Requires macOS 13+ (Swift Package Manager)

## Building

### iOS

Build from command line:

```bash
./build-ios.sh
```

Install to connected device:

```bash
./install-ios.sh
```

Or open `PulseCycle.xcodeproj` in Xcode and build from there.

### macOS

Build release app:

```bash
./build.sh
```

Run the app:

```bash
open PulseCycle.app
```

## Development

### Project Structure

```
PulseCycle/
├── PulseCycleCore/           # Shared framework (iOS + macOS)
│   └── Sources/PulseCycleCore/
│       ├── IntervalEngine.swift    # Timer logic
│       ├── HeartRateMonitor.swift  # Bluetooth heart rate
│       ├── WorkoutProfile.swift    # Profile management
│       └── ...
├── PulseCycle/               # iOS app
│   ├── UI/                   # iOS UIKit views
│   └── iOS/                  # iOS-specific code
├── Sources/PulseCycleMacGUI/ # macOS app (AppKit)
└── Resources/                # macOS resources
```

### Adding PulseCycleCore to iOS

In Xcode:
1. File → Add Package Dependencies
2. Click "Add Local..."
3. Select the `PulseCycleCore` folder
4. Add to the PulseCycle target

## Usage

1. Tap the profile name at the top to select or create workout profiles
2. Configure rounds, durations, and other settings in Settings
3. Tap Go to start the timer
4. Monitor heart rate in real-time (requires BLE chest strap)
5. Tap Pause/Resume to control the workout
6. Tap Reset to stop and reset the timer

## License

Licensed under AGPL-3.0-or-later with additional permissions. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

## Copyright

Copyright © 2026 Jia Liu
