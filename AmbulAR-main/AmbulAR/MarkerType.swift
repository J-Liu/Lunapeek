// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import ARKit

enum MarkerType {
    case start
    case pause
    case resume
    case finish
}

extension MarkerType {
    var color: UIColor {
        switch self {
        case .start: return .systemGreen
        case .pause: return .systemOrange
        case .resume: return .systemBlue
        case .finish: return .systemRed
        }
    }
}
