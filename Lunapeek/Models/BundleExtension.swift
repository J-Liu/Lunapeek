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
            // System language - clear custom bundle and AppleLanguages
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.removeObject(forKey: "AppleTextDirection")
            UserDefaults.standard.synchronize()

            // Clear the associated bundle to use system default
            objc_setAssociatedObject(Bundle.main, &bundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    static func isRTL(language: String?) -> Bool {
        guard let lang = language else { return false }
        return lang.hasPrefix("ar") || lang.hasPrefix("he") || lang.hasPrefix("fa")
    }
}

private class BundleEx: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
