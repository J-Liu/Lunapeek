// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let showHiddenFiles = "showHiddenFiles"
        static let showNonMediaFiles = "showNonMediaFiles"
        static let autoPlayNext = "autoPlayNext"
        static let backgroundPlay = "backgroundPlay"
        static let hardwareDecode = "hardwareDecode"
        static let defaultAspectRatio = "defaultAspectRatio"
        static let repeatMode = "repeatMode"
    }

    // MARK: - File Browser
    var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHiddenFiles) }
        set { defaults.set(newValue, forKey: Key.showHiddenFiles) }
    }

    var showNonMediaFiles: Bool {
        get {
            if defaults.object(forKey: Key.showNonMediaFiles) == nil {
                return false // Default: don't show non-media files
            }
            return defaults.bool(forKey: Key.showNonMediaFiles)
        }
        set { defaults.set(newValue, forKey: Key.showNonMediaFiles) }
    }

    // MARK: - Playback
    var autoPlayNext: Bool {
        get { defaults.bool(forKey: Key.autoPlayNext) }
        set { defaults.set(newValue, forKey: Key.autoPlayNext) }
    }

    var backgroundPlay: Bool {
        get { defaults.bool(forKey: Key.backgroundPlay) }
        set { defaults.set(newValue, forKey: Key.backgroundPlay) }
    }

    var repeatMode: RepeatMode {
        get { RepeatMode(rawValue: defaults.string(forKey: Key.repeatMode) ?? "off") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Key.repeatMode) }
    }

    // MARK: - Video
    var hardwareDecode: HardwareDecode {
        get { HardwareDecode(rawValue: defaults.string(forKey: Key.hardwareDecode) ?? "auto") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.hardwareDecode) }
    }

    var defaultAspectRatio: AspectRatio {
        get { AspectRatio(rawValue: defaults.string(forKey: Key.defaultAspectRatio) ?? "fit") ?? .fit }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultAspectRatio) }
    }

    private init() {
        // Set defaults for boolean values (UserDefaults returns false for missing keys)
        if defaults.object(forKey: Key.autoPlayNext) == nil {
            defaults.set(true, forKey: Key.autoPlayNext)
        }
        if defaults.object(forKey: Key.backgroundPlay) == nil {
            defaults.set(true, forKey: Key.backgroundPlay)
        }
    }
}

enum RepeatMode: String, CaseIterable {
    case off = "off"
    case one = "one"
    case all = "all"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .one: return "Repeat One"
        case .all: return "Repeat All"
        }
    }
}

enum HardwareDecode: String, CaseIterable {
    case auto = "auto"
    case enabled = "enabled"
    case disabled = "disabled"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        }
    }
}

enum AspectRatio: String, CaseIterable {
    case fit = "fit"
    case fill = "fill"
    case stretch = "stretch"

    var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }
}
