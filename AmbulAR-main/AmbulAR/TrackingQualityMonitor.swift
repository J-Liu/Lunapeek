// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import ARKit

enum TrackingQuality: Equatable {
    case normal
    case limited(reason: ARCamera.TrackingState.Reason)
    case notAvailable
}

extension TrackingQuality {
    var message: String? {
        switch self {
        case .normal:
            return nil
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return NSLocalizedString("Moving too fast. Tracking quality reduced.", comment: "")
            case .insufficientFeatures:
                return NSLocalizedString("Low visual features. Tracking quality reduced.", comment: "")
            case .relocalizing:
                return NSLocalizedString("Recovering tracking. Please wait.", comment: "")
            case .initializing:
                return NSLocalizedString("Initializing tracking. Please wait.", comment: "")
            @unknown default:
                return NSLocalizedString("Tracking quality reduced.", comment: "")
            }
        case .notAvailable:
            return NSLocalizedString("Tracking lost. Please restart session.", comment: "")
        }
    }

    var shouldPause: Bool {
        if case .notAvailable = self { return true }
        return false
    }
}

final class TrackingQualityMonitor {

    var onQualityChange: ((TrackingQuality) -> Void)?
    var currentQuality: TrackingQuality { previousQuality }

    private var previousQuality: TrackingQuality = .normal

    func evaluate(trackingState: ARCamera.TrackingState) -> TrackingQuality {
        let quality: TrackingQuality

        switch trackingState {
        case .normal:
            quality = .normal
        case .limited(let reason):
            quality = .limited(reason: reason)
        case .notAvailable:
            quality = .notAvailable
        @unknown default:
            quality = .limited(reason: .initializing)
        }

        if quality != previousQuality {
            onQualityChange?(quality)
            previousQuality = quality
        }

        return quality
    }

    func reset() {
        previousQuality = .normal
    }
}
