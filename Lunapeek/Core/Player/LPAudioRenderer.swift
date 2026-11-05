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
    private let frameQueue = LPFrameQueue<LPAudioFrame>(maxSize: 60)
    private let queue = DispatchQueue(label: "com.lunapeek.audioRenderer")

    // Playback state
    private var _isPlaying = false
    private var isPlaying: Bool {
        get { queue.sync { _isPlaying } }
        set { queue.sync { _isPlaying = newValue } }
    }

    // Audio clock for synchronization
    public let audioClock = LPAudioClock()

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
            // Stop engine if running before reconnecting
            let wasRunning = engine.isRunning
            if wasRunning {
                engine.stop()
            }

            engine.disconnectNodeInput(engine.mainMixerNode)
            engine.connect(playerNode!, to: engine.mainMixerNode, format: format)
            debugLog("🔊 Audio format: \(sampleRate)Hz, \(channels)ch")

            // Restart engine if it was running
            if wasRunning {
                do {
                    try engine.start()
                    debugLog("🔊 Audio engine restarted with new format")
                } catch {
                    debugLog("❌ Failed to restart audio engine: \(error)")
                }
            }
        }
    }

    /// Enqueue a decoded audio frame for playback
    public func enqueue(_ frame: LPAudioFrame) {
        // Configure format from first frame
        if audioFormat == nil {
            configureFormat(sampleRate: frame.sampleRate, channels: frame.channels)
        }

        // Push to frame queue
        _ = frameQueue.push(frame)

        // Process frames if playing
        if isPlaying {
            processFrames()

            // Start engine if not running and we now have a format
            if !engine.isRunning, audioFormat != nil {
                do {
                    try engine.start()
                    debugLog("🔊 Audio renderer started (delayed)")
                    playerNode?.play()
                } catch {
                    debugLog("❌ Failed to start audio engine: \(error)")
                }
            }
        }
    }

    private func processFrames() {
        guard let playerNode = playerNode, isPlaying, audioFormat != nil else { return }

        while let frame = frameQueue.pop(wait: false) {
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
                // Buffer played back - could track progress here
            }
        }
    }

    /// Start playback
    public func play() {
        guard !isPlaying else { return }

        isPlaying = true

        // Start audio clock
        audioClock.resume()

        // Process any queued frames first
        processFrames()

        // Start engine if not running and we have a format
        if !engine.isRunning, audioFormat != nil {
            do {
                try engine.start()
                debugLog("🔊 Audio renderer started")
            } catch {
                debugLog("❌ Failed to start audio engine: \(error)")
                return
            }

            // Start player node
            playerNode?.play()
        }
    }

    /// Pause playback
    public func pause() {
        guard isPlaying else { return }

        isPlaying = false

        // Pause audio clock
        audioClock.pause()

        // Pause player node
        playerNode?.pause()
        engine.pause()
    }

    /// Flush pending frames and reset state
    public func flush() {
        // Clear frame queue
        frameQueue.flush()

        // Reset playing state
        isPlaying = false

        // Reset audio clock
        audioClock.reset()

        // Stop and reset player node
        playerNode?.stop()
    }

    /// Reset the renderer completely
    public func reset() {
        flush()
        engine.stop()
        playerNode?.reset()
        audioFormat = nil
        isPlaying = false
    }

    /// Set volume (0.0 to 1.0)
    public func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    /// Get current volume
    public var volume: Float {
        return engine.mainMixerNode.outputVolume
    }

    /// Get current playback time from audio clock
    public var currentTime: CMTime {
        return audioClock.currentTime
    }

    /// Set playback time (after seek)
    public func setCurrentTime(_ time: CMTime) {
        audioClock.setTime(time)
    }
}
