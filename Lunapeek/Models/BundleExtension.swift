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
        let isLanguageRTL = isRTL(language: language)
        UserDefaults.standard.set([language ?? "system"], forKey: "AppleLanguages")
        UserDefaults.standard.set(isLanguageRTL, forKey: "AppleTextDirection")
        UserDefaults.standard.synchronize()

        object_setClass(Bundle.main, BundleEx.self)
        objc_setAssociatedObject(Bundle.main, &bundleKey, language.flatMap { Bundle(path: Bundle.main.path(forResource: $0, ofType: "lproj") ?? "") }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
