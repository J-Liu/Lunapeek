// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import CoreMotion
import Dispatch

final class MotionMonitor {

    private let pedometer = CMPedometer()
    private let queue = DispatchQueue(label: "com.ambular.motion", qos: .utility)

    var isStepCountingAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    var isDistanceAvailable: Bool {
        CMPedometer.isDistanceAvailable()
    }

    var onMotionEvent: ((Bool) -> Void)?
    var onDistanceUpdate: ((Float) -> Void)?

    private var isWalking = false
    private var lastDistance: Float = 0

    func startMonitoring() {
        guard isStepCountingAvailable else { return }

        pedometer.startEventUpdates { [weak self] event, error in
            guard let self, let event, error == nil else { return }

            DispatchQueue.main.async {
                if event.type == .resume {
                    self.isWalking = true
                    self.onMotionEvent?(true)
                } else if event.type == .pause {
                    self.isWalking = false
                    self.onMotionEvent?(false)
                }
            }
        }

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self, let data, error == nil else { return }

            let distance = Float(data.distance?.doubleValue ?? 0)
            DispatchQueue.main.async {
                self.onDistanceUpdate?(distance)
            }
        }
    }

    func stopMonitoring() {
        pedometer.stopEventUpdates()
        pedometer.stopUpdates()
    }

    func reset() {
        lastDistance = 0
    }
}
