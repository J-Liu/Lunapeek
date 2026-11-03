// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

public protocol IntervalEngineDelegate: AnyObject {
    func engineDidUpdateState(_ engine: IntervalEngine)
    func engineDidTransitionToPhase(_ engine: IntervalEngine, phase: IntervalPhase)
    func engineDidEndPhase(_ engine: IntervalEngine, phase: IntervalPhase)
    func engineDidPlaySound(_ engine: IntervalEngine, sound: String)
    func engineDidSpeak(_ engine: IntervalEngine, text: String)
    func engineDidFinish(_ engine: IntervalEngine)
}

public class IntervalEngine {
    private let config: WorkoutConfig
    public weak var delegate: IntervalEngineDelegate?

    public private(set) var phase: IntervalPhase = .warmUp
    public private(set) var remainingSeconds: Int
    public private(set) var currentRound: Int = 0
    public private(set) var totalElapsedSeconds: Int = 0
    public let totalDuration: Int

    private var timer: Timer?
    private var isRunning = false

    // Phase sequence
    private var phaseSequence: [PhaseItem] = []
    private var currentPhaseIndex: Int = 0

    public var currentPhaseItem: PhaseItem? {
        guard currentPhaseIndex < phaseSequence.count else { return nil }
        return phaseSequence[currentPhaseIndex]
    }

    public init(config: WorkoutConfig) {
        self.config = config
        self.remainingSeconds = config.warmUpSeconds
        self.totalDuration = config.warmUpSeconds +
            (config.workSeconds + config.restSeconds) * config.rounds -
            config.restSeconds + config.coolDownSeconds
    }

    public func start() {
        guard !isRunning else { return }

        // Build phase sequence on first start
        if phaseSequence.isEmpty {
            let profile = ProfileManager.shared.currentProfile
            phaseSequence = PhaseSequenceBuilder.build(from: profile)
            currentPhaseIndex = 0
            phase = phaseSequence[0].phase
            remainingSeconds = phaseSequence[0].duration

            // Play start sound for first phase
            if let startSound = phaseSequence[0].startSound {
                delegate?.engineDidPlaySound(self, sound: startSound)
            }

            // Speak voice text for first phase
            if let voiceText = phaseSequence[0].voiceText {
                delegate?.engineDidSpeak(self, text: voiceText)
            }
        }

        isRunning = true
        scheduleTimer()
    }

    public func pause() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    public func resume() {
        start()
    }

    public func reset() {
        pause()
        phaseSequence = []
        currentPhaseIndex = 0
        phase = .warmUp
        remainingSeconds = config.warmUpSeconds
        currentRound = 0
        totalElapsedSeconds = 0
        delegate?.engineDidUpdateState(self)
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func tick() {
        guard phase != .finished else { return }

        if remainingSeconds > 1 {
            remainingSeconds -= 1
            totalElapsedSeconds += 1

            // Check for warning sound
            if let phaseItem = currentPhaseItem,
               let warningAt = phaseItem.warningAtSeconds,
               remainingSeconds == warningAt,
               let warningSound = phaseItem.warningSound {
                delegate?.engineDidPlaySound(self, sound: warningSound)
            }

            delegate?.engineDidUpdateState(self)
        } else {
            remainingSeconds = 0
            totalElapsedSeconds += 1
            delegate?.engineDidUpdateState(self)
            advancePhase()
        }
    }

    private func advancePhase() {
        let endedPhaseItem = currentPhaseItem

        // Play end sound if configured
        if let endSound = endedPhaseItem?.endSound {
            delegate?.engineDidPlaySound(self, sound: endSound)
        }

        // Move to next phase
        currentPhaseIndex += 1

        if currentPhaseIndex >= phaseSequence.count {
            // All phases completed
            phase = .finished
            remainingSeconds = 0
            pause()
            delegate?.engineDidFinish(self)
        } else {
            // Transition to next phase
            let nextPhaseItem = phaseSequence[currentPhaseIndex]
            phase = nextPhaseItem.phase
            remainingSeconds = nextPhaseItem.duration

            // Update currentRound for work/rest phases
            if phase == .work {
                currentRound += 1
            }

            // Play start sound if configured
            if let startSound = nextPhaseItem.startSound {
                delegate?.engineDidPlaySound(self, sound: startSound)
            }

            // Speak voice text if configured
            if let voiceText = nextPhaseItem.voiceText {
                delegate?.engineDidSpeak(self, text: voiceText)
            }

            delegate?.engineDidTransitionToPhase(self, phase: phase)
        }

        delegate?.engineDidUpdateState(self)
    }
}
