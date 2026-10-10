// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

private var bundleKey: UInt8 = 0

extension Bundle {
    static let once: Void = {
        object_setClass(Bundle.main, BundleEx.self)
    }()

    static func setLanguage(_ language: String?) {
        Bundle.once

        // Determine the actual language to use
        let targetLanguage: String
        if let lang = language {
            targetLanguage = lang
        } else {
            // System language - get from device settings
            targetLanguage = mapSystemLanguage(Locale.preferredLanguages.first ?? "en")
        }

        // Apply the language
        let isLanguageRTL = isRTL(language: targetLanguage)
        objc_setAssociatedObject(Bundle.main, &bundleKey,
            Bundle(path: Bundle.main.path(forResource: targetLanguage, ofType: "lproj") ?? ""),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Update AppleLanguages for system consistency
        UserDefaults.standard.set([targetLanguage], forKey: "AppleLanguages")
        UserDefaults.standard.set(isLanguageRTL, forKey: "AppleTextDirection")
        UserDefaults.standard.synchronize()
    }

    /// Map system language to our supported language codes
    static func mapSystemLanguage(_ language: String) -> String {
        // Handle Chinese variants
        if language.hasPrefix("zh-Hans") || language == "zh-CN" {
            return "zh-Hans"
        }
        if language.hasPrefix("zh-Hant") || language == "zh-TW" || language == "zh-HK" || language == "zh-MO" {
            return "zh-Hant"
        }
        // Handle other languages - extract base language code
        let baseLanguage = language.components(separatedBy: "-").first ?? language
        // Check if we have a localization for this language
        let availableLocalizations = Bundle.main.localizations
        if availableLocalizations.contains(baseLanguage) {
            return baseLanguage
        }
        // Default to English if not supported
        return "en"
    }

    static func isRTL(language: String?) -> Bool {
        guard let lang = language else { return false }
        return lang.hasPrefix("ar") || lang.hasPrefix("he") || lang.hasPrefix("fa")
    }
}

private class BundleEx: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
