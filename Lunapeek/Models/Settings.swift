// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import AVFoundation

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let showHiddenFiles = "showHiddenFiles"
        static let showNonMediaFiles = "showNonMediaFiles"
        static let autoPlayNext = "autoPlayNext"
        static let backgroundPlay = "backgroundPlay"
        static let defaultAspectRatio = "defaultAspectRatio"
        static let repeatMode = "repeatMode"
        static let exitBehavior = "exitBehavior"
        static let language = "language"
    }

    // MARK: - Language
    var language: Language {
        get { Language(rawValue: defaults.string(forKey: Key.language) ?? "system") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: Key.language)
            LanguageManager.shared.applyLanguage(newValue)
        }
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

    var showThumbnails: Bool {
        get { defaults.bool(forKey: "showThumbnails") }
        set { defaults.set(newValue, forKey: "showThumbnails") }
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
    var defaultAspectRatio: AspectRatio {
        get { AspectRatio(rawValue: defaults.string(forKey: Key.defaultAspectRatio) ?? "fit") ?? .fit }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultAspectRatio) }
    }

    var exitBehavior: ExitBehavior {
        get { ExitBehavior(rawValue: defaults.string(forKey: Key.exitBehavior) ?? "pip") ?? .pip }
        set { defaults.set(newValue.rawValue, forKey: Key.exitBehavior) }
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

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        case .stretch: return .resize
        }
    }
}

enum ExitBehavior: String, CaseIterable {
    case pip = "pip"
    case background = "background"
    case pause = "pause"

    var displayName: String {
        switch self {
        case .pip: return "Picture in Picture"
        case .background: return "Background Play"
        case .pause: return "Pause"
        }
    }
}
