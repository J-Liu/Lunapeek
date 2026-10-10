// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import UIKit

enum Language: String, CaseIterable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var displayName: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    var locale: Locale? {
        switch self {
        case .system:
            // Get actual system language
            let systemLang = Locale.preferredLanguages.first ?? "en"
            return Locale(identifier: systemLang)
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .traditionalChinese:
            return Locale(identifier: "zh-Hant")
        }
    }

}

final class LanguageManager {
    static let shared = LanguageManager()

    private init() {}

    func applyLanguage(_ language: Language) {
        // Save language preference
        UserDefaults.standard.set(language.rawValue, forKey: "language")
        UserDefaults.standard.synchronize()

        // Apply language using Bundle extension for real-time switching
        Bundle.setLanguage(language)

        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    var currentLanguage: Language {
        let stored = UserDefaults.standard.string(forKey: "language") ?? "system"
        return Language(rawValue: stored) ?? .system
    }

    var currentLocale: Locale {
        return currentLanguage.locale ?? Locale.current
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

func L(_ key: String) -> String {
    return NSLocalizedString(key, comment: "")
}

/// Get DateFormatter with current language locale
func makeDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = LanguageManager.shared.currentLocale
    return formatter
}
