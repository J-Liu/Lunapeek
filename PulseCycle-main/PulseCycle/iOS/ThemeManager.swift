// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu

import UIKit

extension Notification.Name {
    static let themeChanged = Notification.Name("themeChanged")
}

/// Supported themes for the app
enum Theme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "")
        case .light:
            return NSLocalizedString("Light", comment: "")
        case .dark:
            return NSLocalizedString("Dark", comment: "")
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// Manages app theme settings
final class ThemeManager {
    static let shared = ThemeManager()

    private let themeKey = "appTheme"

    var currentTheme: Theme {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: themeKey),
               let theme = Theme(rawValue: rawValue) {
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

    func applyTheme(_ theme: Theme) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = theme.userInterfaceStyle
            }
        }
    }
}
