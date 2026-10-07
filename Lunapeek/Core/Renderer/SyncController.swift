// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import CoreMedia
import QuartzCore

/// Clock for media synchronization.
public final class MediaClock {
    private var startTime: CMTime = .zero
    private var pauseTime: CMTime = .zero
    private var isPaused: Bool = true
    private let lock = NSLock()

    public init() {}

    public var currentTime: CMTime {
        lock.lock()
        defer { lock.unlock() }

        guard !isPaused else {
            return pauseTime
        }

        let elapsed = CACurrentMediaTime() - startTime.seconds
        return CMTime(seconds: elapsed, preferredTimescale: 1000000)
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        if isPaused {
            startTime = CMTime(
                seconds: CACurrentMediaTime() - pauseTime.seconds,
                preferredTimescale: 1000000
            )
            isPaused = false
        }
    }

    public func pause() {
        lock.lock()
        defer { lock.unlock() }

        if !isPaused {
            pauseTime = currentTime
            isPaused = true
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        startTime = .zero
        pauseTime = .zero
        isPaused = true
    }

    public func setTime(_ time: CMTime) {
        lock.lock()
        defer { lock.unlock() }

        startTime = CMTime(
            seconds: CACurrentMediaTime() - time.seconds,
            preferredTimescale: 1000000
        )
        pauseTime = time
    }
}

/// Frame synchronizer for audio-video sync.
public final class FrameSynchronizer {
    private let audioClock = MediaClock()
    private var videoQueue: [VideoFrame] = []
    private var audioQueue: [AudioSamples] = []
    private let maxVideoQueueSize = 10
    private let maxAudioQueueSize = 20
    private let lock = NSLock()

    public var clockTime: CMTime {
        return audioClock.currentTime
    }

    public func start() {
        audioClock.start()
    }

    public func pause() {
        audioClock.pause()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        audioClock.reset()
        videoQueue.removeAll()
        audioQueue.removeAll()
    }

    public func enqueueVideo(_ frame: VideoFrame) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard videoQueue.count < maxVideoQueueSize else {
            return false
        }

        videoQueue.append(frame)
        return true
    }

    public func enqueueAudio(_ samples: AudioSamples) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard audioQueue.count < maxAudioQueueSize else {
            return false
        }

        audioQueue.append(samples)
        return true
    }

    public func getNextVideoFrame() -> VideoFrame? {
        lock.lock()
        defer { lock.unlock() }

        guard let frame = videoQueue.first else {
            return nil
        }

        // Check if it's time to display this frame
        let displayTime = CMTime(
            seconds: Double(frame.presentationTimestamp) / 1_000_000,
            preferredTimescale: 1_000_000
        )

        let currentClock = audioClock.currentTime

        // Drop frames that are too late
        if displayTime.seconds < currentClock.seconds - 0.1 {
            videoQueue.removeFirst()
            return getNextVideoFrame()
        }

        // Return frame if it's time to display (within 50ms tolerance)
        if abs(displayTime.seconds - currentClock.seconds) < 0.05 {
            videoQueue.removeFirst()
            return frame
        }

        // Frame is in the future
        return nil
    }

    public func getNextAudioSamples() -> AudioSamples? {
        lock.lock()
        defer { lock.unlock() }

        guard let samples = audioQueue.first else {
            return nil
        }

        audioQueue.removeFirst()
        return samples
    }

    public var videoQueueSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return videoQueue.count
    }

    public var audioQueueSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return audioQueue.count
    }
}
