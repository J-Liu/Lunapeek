// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import simd
import ARKit

final class SessionController {

    var state: TrackingState = .idle
    var totalDistance: Float { sensorFusion.fusedDistance }
    var currentTrackingQuality: TrackingQuality { qualityMonitor.currentQuality }

    private let distanceTracker = DistanceTracker()
    private let sensorFusion = SensorFusion()
    private let qualityMonitor = TrackingQualityMonitor()
    private var pausedPosition: simd_float3?

    var onQualityChange: ((TrackingQuality) -> Void)? {
        get { qualityMonitor.onQualityChange }
        set { qualityMonitor.onQualityChange = newValue }
    }

    func startTracking() {
        sensorFusion.start()
    }

    func stopTracking() {
        sensorFusion.stop()
    }

    func handleAction() {
        switch state {
        case .idle:
            state = .tracking
            distanceTracker.reset()
            sensorFusion.reset()
            sensorFusion.start()
            qualityMonitor.reset()
        case .tracking:
            state = .paused
        case .paused:
            state = .tracking
        case .finished:
            state = .idle
            distanceTracker.reset()
            sensorFusion.reset()
            qualityMonitor.reset()
        }
    }

    func finish() {
        state = .finished
        sensorFusion.stop()
    }

    func update(with position: simd_float3, trackingState: ARCamera.TrackingState) {
        guard state == .tracking else { return }

        let quality = qualityMonitor.evaluate(trackingState: trackingState)

        if quality.shouldPause {
            return
        }

        if pausedPosition != nil {
            distanceTracker.reset()
            distanceTracker.update(with: position)
            pausedPosition = nil
        } else {
            distanceTracker.update(with: position)
        }

        sensorFusion.updateARKitDistance(distanceTracker.currentDistance, trackingState: trackingState)
    }

    func setPausedPosition(_ position: simd_float3) {
        pausedPosition = position
    }
}
