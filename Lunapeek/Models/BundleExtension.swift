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

        if let lang = language {
            // Specific language selected
            let isLanguageRTL = isRTL(language: lang)
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
            UserDefaults.standard.set(isLanguageRTL, forKey: "AppleTextDirection")
            UserDefaults.standard.synchronize()

            object_setClass(Bundle.main, BundleEx.self)
            let bundle = Bundle(path: Bundle.main.path(forResource: lang, ofType: "lproj") ?? "")
            objc_setAssociatedObject(Bundle.main, &bundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } else {
            // System language - get actual system language and map to supported language
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            let supportedLanguage = mapSystemLanguage(systemLanguage)
            let isLanguageRTL = isRTL(language: supportedLanguage)

            UserDefaults.standard.set([supportedLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.set(isLanguageRTL, forKey: "AppleTextDirection")
            UserDefaults.standard.synchronize()

            // Set the system language bundle
            object_setClass(Bundle.main, BundleEx.self)
            let bundle = Bundle(path: Bundle.main.path(forResource: supportedLanguage, ofType: "lproj") ?? "")
            objc_setAssociatedObject(Bundle.main, &bundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
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
