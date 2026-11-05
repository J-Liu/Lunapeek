// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import Foundation

/// Audio renderer using AVAudioEngine for PCM playback
public final class LPAudioRenderer {
    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var pendingFrames: [LPAudioFrame] = []
    private let queue = DispatchQueue(label: "com.lunapeek.audioRenderer")

    // Thread-safe playing state
    private var _isPlaying = false
    private var isPlaying: Bool {
        get { queue.sync { _isPlaying } }
        set { queue.sync { _isPlaying = newValue } }
    }

    public init() {
        setupEngine()
    }

    private func setupEngine() {
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode!)

        // Connect to main mixer
        engine.connect(playerNode!, to: engine.mainMixerNode, format: nil)
    }

    /// Configure with audio format from first frame
    private func configureFormat(sampleRate: Int32, channels: Int32) {
        guard audioFormat == nil else { return }

        // Create PCM format (signed 16-bit interleaved)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true
        )

        self.audioFormat = format

        if let format = format {
            engine.disconnectNodeInput(engine.mainMixerNode)
            engine.connect(playerNode!, to: engine.mainMixerNode, format: format)
            debugLog("🔊 Audio format: \(sampleRate)Hz, \(channels)ch")
        }
    }

    /// Enqueue a decoded audio frame for playback
    public func enqueue(_ frame: LPAudioFrame) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingFrames.append(frame)
            // Process if already playing
            if self._isPlaying {
                self.processPendingFrames()
            }
        }
    }

    private func processPendingFrames() {
        // Called on queue, so _isPlaying is safe to access
        guard let playerNode = playerNode, _isPlaying, audioFormat != nil else { return }

        while !pendingFrames.isEmpty {
            let frame = pendingFrames.removeFirst()

            guard let format = audioFormat else { continue }

            // Create audio buffer
            let frameCount = AVAudioFrameCount(frame.data.count / Int(frame.channels * 2))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }

            buffer.frameLength = frameCount

            // Copy data to buffer
            frame.data.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    memcpy(buffer.int16ChannelData![0], baseAddress, frame.data.count)
                }
            }

            // Schedule buffer
            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                // Buffer played back
            }
        }
    }

    /// Start playback
    public func play() {
        // Get first frame info and set playing state on queue
        var firstFrameInfo: (sampleRate: Int32, channels: Int32)?
        var wasPlaying = false
        queue.sync {
            wasPlaying = _isPlaying
            if let firstFrame = pendingFrames.first {
                firstFrameInfo = (firstFrame.sampleRate, firstFrame.channels)
            }
        }

        guard !wasPlaying else { return }

        // Configure format from first pending frame if needed
        if let info = firstFrameInfo, audioFormat == nil {
            configureFormat(sampleRate: info.sampleRate, channels: info.channels)
        }

        do {
            try engine.start()
            playerNode?.play()
            debugLog("🔊 Audio renderer started")
            // Set playing state and process frames on queue
            queue.async { [weak self] in
                guard let self = self else { return }
                self._isPlaying = true
                self.processPendingFrames()
            }
        } catch {
            debugLog("❌ Failed to start audio engine: \(error)")
        }
    }

    /// Pause playback
    public func pause() {
        queue.sync {
            guard _isPlaying else { return }
            _isPlaying = false
        }
        playerNode?.pause()
        engine.pause()
    }

    /// Flush pending frames
    public func flush() {
        queue.async { [weak self] in
            self?.pendingFrames.removeAll()
        }
        playerNode?.stop()
    }

    /// Reset the renderer
    public func reset() {
        flush()
        engine.stop()
        playerNode?.reset()
        audioFormat = nil
        queue.sync {
            _isPlaying = false
        }
    }

    /// Set volume (0.0 to 1.0)
    public func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    /// Get current volume
    public var volume: Float {
        return engine.mainMixerNode.outputVolume
    }
}
