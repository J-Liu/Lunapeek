// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

public struct PhaseItem {
    public let phase: IntervalPhase
    public let duration: Int
    public let color: String
    public let startSound: String?
    public let endSound: String?
    public let tickSound: String?
    public let warningAtSeconds: Int?
    public let warningSound: String?
    public let voiceText: String?

    public static func warmUp(_ profile: WorkoutProfile) -> PhaseItem {
        return PhaseItem(
            phase: .warmUp,
            duration: profile.warmUpSeconds,
            color: profile.warmUpColor,
            startSound: profile.startSoundEnabled ? "boxing-bell-1" : nil,
            endSound: nil,
            tickSound: nil,
            warningAtSeconds: nil,
            warningSound: nil,
            voiceText: profile.voiceOutputEnabled && profile.warmUpSeconds >= 5 ? "Warm up" : nil
        )
    }

    public static func work(_ profile: WorkoutProfile, roundNumber: Int) -> PhaseItem {
        return PhaseItem(
            phase: .work,
            duration: profile.workSeconds,
            color: profile.workColor,
            startSound: profile.startSoundEnabled ? "boxing-bell-1" : nil,
            endSound: profile.endSoundEnabled ? "boxing-bell-3" : nil,
            tickSound: nil,
            warningAtSeconds: profile.workSeconds >= 15 ? 10 : nil,
            warningSound: profile.endingNotifySoundEnabled ? "boxing-bell-2" : nil,
            voiceText: profile.voiceOutputEnabled && profile.workSeconds >= 5 ? "Round \(roundNumber)" : nil
        )
    }

    public static func rest(_ profile: WorkoutProfile) -> PhaseItem {
        return PhaseItem(
            phase: .rest,
            duration: profile.restSeconds,
            color: profile.restColor,
            startSound: nil,
            endSound: nil,
            tickSound: nil,
            warningAtSeconds: nil,
            warningSound: nil,
            voiceText: nil
        )
    }

    public static func coolDown(_ profile: WorkoutProfile) -> PhaseItem {
        return PhaseItem(
            phase: .coolDown,
            duration: profile.coolDownSeconds,
            color: profile.coolDownColor,
            startSound: nil,
            endSound: profile.endSoundEnabled ? "boxing-bell-3" : nil,
            tickSound: nil,
            warningAtSeconds: nil,
            warningSound: nil,
            voiceText: profile.voiceOutputEnabled && profile.coolDownSeconds >= 5 ? "Cool down" : nil
        )
    }
}

public class PhaseSequenceBuilder {
    public static func build(from profile: WorkoutProfile) -> [PhaseItem] {
        var items: [PhaseItem] = []

        // Warm-up
        if profile.warmUpEnabled {
            items.append(.warmUp(profile))
        }

        // Work/Rest rounds
        for i in 0..<profile.rounds {
            items.append(.work(profile, roundNumber: i + 1))

            // Add rest after each work except the last one
            if i < profile.rounds - 1 {
                items.append(.rest(profile))
            }
        }

        // Cool-down
        if profile.coolDownEnabled {
            items.append(.coolDown(profile))
        }

        return items
    }
}
