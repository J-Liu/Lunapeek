// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import ObjectiveC

private var bundleKey: UInt8 = 0

final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let path = objc_getAssociatedObject(self, &bundleKey) as? String,
              let bundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        let result = bundle.localizedString(forKey: key, value: value, table: tableName)
        return result
    }
}

extension Bundle {
    static func setLanguage(_ language: AppLanguage) {
        object_setClass(Bundle.main, LanguageBundle.self)

        var bundlePath: String?

        // Get all available localizations
        let availableLocalizations = Bundle.main.localizations
        print("[Language] Available localizations: \(availableLocalizations)")

        switch language {
        case .system:
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            print("[Language] System preferred: \(preferredLanguage)")
            if preferredLanguage.hasPrefix("zh-Hant") {
                bundlePath = Bundle.main.path(forResource: "zh-Hant", ofType: "lproj")
            } else if preferredLanguage.hasPrefix("zh-Hans") || preferredLanguage.hasPrefix("zh-CN") || preferredLanguage.hasPrefix("zh") {
                bundlePath = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj")
            } else {
                bundlePath = Bundle.main.path(forResource: "en", ofType: "lproj")
            }
        case .english:
            bundlePath = Bundle.main.path(forResource: "en", ofType: "lproj")
        case .simplifiedChinese:
            bundlePath = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj")
        case .traditionalChinese:
            bundlePath = Bundle.main.path(forResource: "zh-Hant", ofType: "lproj")
        }

        if let path = bundlePath {
            objc_setAssociatedObject(Bundle.main, &bundleKey, path, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            print("[Language] Set to \(language.rawValue), path: \(path)")
        } else {
            let fallback = Bundle.main.path(forResource: "en", ofType: "lproj") ?? ""
            objc_setAssociatedObject(Bundle.main, &bundleKey, fallback, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            print("[Language] Fallback to en, path: \(fallback)")
        }
    }
}
