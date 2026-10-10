// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

enum DistanceUnit: String, CaseIterable {
    case meters = "m"
    case kilometers = "km"
    case feet = "ft"
    case miles = "mi"

    var title: String {
        switch self {
        case .meters: return "Meters"
        case .kilometers: return "Kilometers"
        case .feet: return "Feet"
        case .miles: return "Miles"
        }
    }

    var localizedName: String {
        switch self {
        case .meters: return NSLocalizedString("Meters", comment: "")
        case .kilometers: return NSLocalizedString("Kilometers", comment: "")
        case .feet: return NSLocalizedString("Feet", comment: "")
        case .miles: return NSLocalizedString("Miles", comment: "")
        }
    }

    func format(_ meters: Float) -> String {
        switch self {
        case .meters:
            return String(format: "%.3f m", meters)
        case .kilometers:
            return String(format: "%.3f km", meters / 1000)
        case .feet:
            return String(format: "%.1f ft", meters * 3.28084)
        case .miles:
            return String(format: "%.3f mi", meters / 1609.344)
        }
    }

    static var current: DistanceUnit {
        if let saved = UserDefaults.standard.string(forKey: "SelectedUnit"),
           let unit = DistanceUnit(rawValue: saved) {
            return unit
        }
        return .meters
    }
}
