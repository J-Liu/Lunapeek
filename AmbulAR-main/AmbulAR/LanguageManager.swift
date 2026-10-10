// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("System Default", comment: "")
        case .english: return NSLocalizedString("English", comment: "")
        case .simplifiedChinese: return NSLocalizedString("Simplified Chinese", comment: "")
        case .traditionalChinese: return NSLocalizedString("Traditional Chinese", comment: "")
        }
    }
}

final class LanguageManager {

    static let shared = LanguageManager()
    static let languageChangedNotification = Notification.Name("LanguageChangedNotification")

    private let userDefaultsKey = "AppLanguage"

    var currentLanguage: AppLanguage {
        get {
            if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
               let language = AppLanguage(rawValue: saved) {
                return language
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            applyLanguage(newValue)
            NotificationCenter.default.post(name: Self.languageChangedNotification, object: nil)
        }
    }

    var currentLocale: Locale {
        switch currentLanguage {
        case .system:
            return Locale.current
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .traditionalChinese:
            return Locale(identifier: "zh-Hant")
        }
    }

    private init() {
        applyLanguage(currentLanguage)
    }

    func applyLanguage(_ language: AppLanguage) {
        Bundle.setLanguage(language)
    }
}
