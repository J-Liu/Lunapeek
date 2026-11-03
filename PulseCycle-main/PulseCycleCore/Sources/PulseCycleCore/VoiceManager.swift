// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AVFoundation

public class VoiceManager {
    public static let shared = VoiceManager()

    private let synthesizer = AVSpeechSynthesizer()
    private let englishVoice = AVSpeechSynthesisVoice(language: "en-US")

    private init() {
        // Configure audio session for playback (iOS)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    public func speak(_ text: String) {
        // Stop any ongoing speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = englishVoice
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    public func speakWarmUp() {
        speak("Warm up")
    }

    public func speakRound(_ roundNumber: Int) {
        speak("Round \(roundNumber)")
    }

    public func speakCoolDown() {
        speak("Cool down")
    }
}
