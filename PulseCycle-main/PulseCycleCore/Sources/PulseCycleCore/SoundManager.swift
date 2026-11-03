// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AVFoundation

public class SoundManager {
    public static let shared = SoundManager()

    private var audioPlayers: [String: AVAudioPlayer] = [:]

    // Available sounds
    public static let availableSounds = [
        "boxing-bell-1",
        "boxing-bell-2",
        "boxing-bell-3",
        "countdown_beep"
    ]

    private init() {
        preloadSounds()
    }

    private func preloadSounds() {
        for soundName in SoundManager.availableSounds {
            if let url = Bundle.main.url(forResource: soundName, withExtension: "wav") {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    audioPlayers[soundName] = player
                } catch {
                    // Silently skip failed sound loads
                }
            }
        }
    }

    public func playSound(_ soundName: String) {
        guard let player = audioPlayers[soundName] else {
            return
        }

        player.currentTime = 0
        player.play()
    }

    public func playCountdownBeep() {
        playSound("countdown_beep")
    }

    public func playPhaseStartSound() {
        playSound("boxing-bell-1")
    }

    public func playPreRoundWarningSound() {
        playSound("boxing-bell-2")
    }

    public func playRoundEndSound() {
        playSound("boxing-bell-3")
    }
}
