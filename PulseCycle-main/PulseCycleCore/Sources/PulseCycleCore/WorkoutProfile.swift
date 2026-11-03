// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

public struct WorkoutProfile: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var rounds: Int
    public var workSeconds: Int
    public var restSeconds: Int
    public var prepareTime: Int
    public var warmUpSeconds: Int
    public var warmUpEnabled: Bool
    public var coolDownSeconds: Int
    public var coolDownEnabled: Bool
    public var prepareCountingSoundEnabled: Bool
    public var startSoundEnabled: Bool
    public var endingNotifySoundEnabled: Bool
    public var endSoundEnabled: Bool
    public var voiceOutputEnabled: Bool
    public var workColor: String
    public var restColor: String
    public var heartRateColor: String
    public var prepareColor: String
    public var warmUpColor: String
    public var coolDownColor: String

    public static var defaultProfiles: [WorkoutProfile] {
        [
            WorkoutProfile(
                id: UUID(),
                name: "Amateur Boxing",
                rounds: 4,
                workSeconds: 120,
                restSeconds: 60,
                prepareTime: 5,
                warmUpSeconds: 180,
                warmUpEnabled: false,
                coolDownSeconds: 180,
                coolDownEnabled: false,
                prepareCountingSoundEnabled: true,
                startSoundEnabled: true,
                endingNotifySoundEnabled: true,
                endSoundEnabled: true,
                voiceOutputEnabled: true,
                workColor: "#FF6B6B",
                restColor: "#E0E0E0",
                heartRateColor: "#FF8A80",
                prepareColor: "#FFAAAA",
                warmUpColor: "#FF8888",
                coolDownColor: "#E8A0A0"
            ),
            WorkoutProfile(
                id: UUID(),
                name: "MMA",
                rounds: 5,
                workSeconds: 300,
                restSeconds: 60,
                prepareTime: 5,
                warmUpSeconds: 300,
                warmUpEnabled: false,
                coolDownSeconds: 300,
                coolDownEnabled: false,
                prepareCountingSoundEnabled: true,
                startSoundEnabled: true,
                endingNotifySoundEnabled: true,
                endSoundEnabled: true,
                voiceOutputEnabled: true,
                workColor: "#FF6B6B",
                restColor: "#E0E0E0",
                heartRateColor: "#FF8A80",
                prepareColor: "#FFAAAA",
                warmUpColor: "#FF8888",
                coolDownColor: "#E8A0A0"
            ),
            WorkoutProfile(
                id: UUID(),
                name: "Classic Boxing",
                rounds: 12,
                workSeconds: 180,
                restSeconds: 60,
                prepareTime: 5,
                warmUpSeconds: 180,
                warmUpEnabled: false,
                coolDownSeconds: 180,
                coolDownEnabled: false,
                prepareCountingSoundEnabled: true,
                startSoundEnabled: true,
                endingNotifySoundEnabled: true,
                endSoundEnabled: true,
                voiceOutputEnabled: true,
                workColor: "#FF6B6B",
                restColor: "#E0E0E0",
                heartRateColor: "#FF8A80",
                prepareColor: "#FFAAAA",
                warmUpColor: "#FF8888",
                coolDownColor: "#E8A0A0"
            ),
            WorkoutProfile(
                id: UUID(),
                name: "Boxing Training",
                rounds: 3,
                workSeconds: 300,
                restSeconds: 60,
                prepareTime: 5,
                warmUpSeconds: 600,
                warmUpEnabled: true,
                coolDownSeconds: 600,
                coolDownEnabled: true,
                prepareCountingSoundEnabled: true,
                startSoundEnabled: true,
                endingNotifySoundEnabled: true,
                endSoundEnabled: true,
                voiceOutputEnabled: true,
                workColor: "#FF6B6B",
                restColor: "#E0E0E0",
                heartRateColor: "#FF8A80",
                prepareColor: "#FFAAAA",
                warmUpColor: "#FF8888",
                coolDownColor: "#E8A0A0"
            ),
            WorkoutProfile(
                id: UUID(),
                name: "Jump Rope",
                rounds: 5,
                workSeconds: 120,
                restSeconds: 60,
                prepareTime: 5,
                warmUpSeconds: 120,
                warmUpEnabled: false,
                coolDownSeconds: 120,
                coolDownEnabled: false,
                prepareCountingSoundEnabled: true,
                startSoundEnabled: true,
                endingNotifySoundEnabled: true,
                endSoundEnabled: true,
                voiceOutputEnabled: true,
                workColor: "#FF6B6B",
                restColor: "#E0E0E0",
                heartRateColor: "#FF8A80",
                prepareColor: "#FFAAAA",
                warmUpColor: "#FF8888",
                coolDownColor: "#E8A0A0"
            )
        ]
    }

    public static var defaultProfile: WorkoutProfile {
        return defaultProfiles[0]
    }
}

public class ProfileManager {
    public static let shared = ProfileManager()

    private let userDefaultsKey = "workout_profiles"
    private let currentProfileIndexKey = "current_profile_index"
    public private(set) var profiles: [WorkoutProfile]
    public private(set) var currentProfileIndex: Int = 0 {
        didSet {
            UserDefaults.standard.set(currentProfileIndex, forKey: currentProfileIndexKey)
        }
    }

    public var currentProfile: WorkoutProfile {
        profiles[currentProfileIndex]
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([WorkoutProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = WorkoutProfile.defaultProfiles
        }

        // Restore last selected profile index
        currentProfileIndex = UserDefaults.standard.integer(forKey: currentProfileIndexKey)
        if currentProfileIndex >= profiles.count {
            currentProfileIndex = 0
        }
    }

    public func save() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    public func addProfile(copyFrom profile: WorkoutProfile, name: String? = nil) -> WorkoutProfile {
        var newProfile = profile
        newProfile.id = UUID()
        newProfile.name = name ?? "\(profile.name) Copy"
        profiles.append(newProfile)
        save()
        return newProfile
    }

    public func deleteProfile(at index: Int) {
        guard profiles.count > 1, index < profiles.count else { return }
        profiles.remove(at: index)
        if currentProfileIndex >= profiles.count {
            currentProfileIndex = profiles.count - 1
        }
    }

    public func selectProfile(at index: Int) {
        guard index < profiles.count else { return }
        currentProfileIndex = index
    }

    public func updateProfile(_ profile: WorkoutProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            save()
        }
    }
}
