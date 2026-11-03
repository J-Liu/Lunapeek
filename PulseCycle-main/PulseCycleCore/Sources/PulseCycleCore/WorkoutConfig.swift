// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

public struct WorkoutConfig {
    public let warmUpSeconds: Int
    public let workSeconds: Int
    public let restSeconds: Int
    public let rounds: Int
    public let coolDownSeconds: Int

    public init(warmUpSeconds: Int, workSeconds: Int, restSeconds: Int, rounds: Int, coolDownSeconds: Int) {
        self.warmUpSeconds = warmUpSeconds
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.rounds = rounds
        self.coolDownSeconds = coolDownSeconds
    }
}
