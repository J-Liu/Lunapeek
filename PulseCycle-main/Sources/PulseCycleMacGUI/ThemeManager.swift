// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

extension Notification.Name {
    static let themeChanged = Notification.Name("themeChanged")
}

/// Supported themes for the app
enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system:
            return L("settings.theme.system")
        case .light:
            return L("settings.theme.light")
        case .dark:
            return L("settings.theme.dark")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

/// Manages app theme settings
final class ThemeManager {
    static let shared = ThemeManager()

    private let themeKey = "appTheme"

    var currentTheme: AppTheme {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: themeKey),
               let theme = AppTheme(rawValue: rawValue) {
                return theme
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: themeKey)
            applyTheme(newValue)
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    private init() {
        applyTheme(currentTheme)
    }

    func applyTheme(_ theme: AppTheme) {
        if let appearance = theme.appearance {
            NSApp.appearance = appearance
        } else {
            NSApp.appearance = nil
        }
    }
}
