// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import simd

final class DistanceTracker {

    private(set) var accumulatedDistance: Float = 0
    private var startPosition: simd_float3?
    private var previousPosition: simd_float3?

    var currentDistance: Float {
        return accumulatedDistance
    }

    func update(with position: simd_float3) {
        if startPosition == nil {
            startPosition = position
            previousPosition = position
            return
        }

        guard let previous = previousPosition else { return }

        let dx = position.x - previous.x
        let dz = position.z - previous.z
        let horizontalDistance = sqrt(dx * dx + dz * dz)

        accumulatedDistance += horizontalDistance
        previousPosition = position
    }

    func reset() {
        accumulatedDistance = 0
        startPosition = nil
        previousPosition = nil
    }
}
