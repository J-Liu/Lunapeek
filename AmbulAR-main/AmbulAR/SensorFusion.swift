// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import ARKit
import simd

final class SensorFusion {

    private let motionMonitor = MotionMonitor()

    var isWalking: Bool = true
    var arkitDistance: Float = 0
    var motionDistance: Float = 0
    var fusedDistance: Float { arkitDistance }

    private var lastArkitDistance: Float = 0
    private var lastMotionDistance: Float = 0
    private var trackingLostDistance: Float = 0
    private var isTrackingLost: Bool = false

    var onMotionEvent: ((Bool) -> Void)? {
        get { motionMonitor.onMotionEvent }
        set { motionMonitor.onMotionEvent = newValue }
    }

    var onMotionDistanceUpdate: ((Float) -> Void)? {
        get { motionMonitor.onDistanceUpdate }
        set { motionMonitor.onDistanceUpdate = newValue }
    }

    func start() {
        motionMonitor.startMonitoring()

        motionMonitor.onMotionEvent = { [weak self] walking in
            guard let self else { return }
            self.isWalking = walking
        }

        motionMonitor.onDistanceUpdate = { [weak self] distance in
            guard let self else { return }
            self.motionDistance = distance
        }
    }

    func stop() {
        motionMonitor.stopMonitoring()
    }

    func updateARKitDistance(_ distance: Float, trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            if isTrackingLost {
                isTrackingLost = false
                trackingLostDistance = 0
            }
            let delta = distance - lastArkitDistance
            if !isWalking && abs(delta) > 0.5 {
                arkitDistance = lastArkitDistance
            } else {
                arkitDistance = distance
            }
            lastArkitDistance = arkitDistance

        case .limited:
            if !isTrackingLost {
                isTrackingLost = true
                trackingLostDistance = arkitDistance
            }
            let motionDelta = motionDistance - lastMotionDistance
            arkitDistance = trackingLostDistance + motionDelta
            lastMotionDistance = motionDistance

        case .notAvailable:
            break
        @unknown default:
            break
        }
    }

    func reset() {
        arkitDistance = 0
        motionDistance = 0
        lastArkitDistance = 0
        lastMotionDistance = 0
        trackingLostDistance = 0
        isTrackingLost = false
        motionMonitor.reset()
    }
}
