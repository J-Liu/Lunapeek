// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import Foundation

/// Audio clock for A/V synchronization
/// Uses audio playback time as the master clock
public final class LPAudioClock {
    private var startTime: CMTime = .zero  // Video position when playback started
    private var wallClockStart: Double = 0  // Wall clock time when playback started
    private var pauseTime: CMTime = .zero
    private var isPlaying = false
    private let lock = NSLock()

    public init() {}

    /// Start the clock at a given time (video position)
    public func start(at time: CMTime = .zero) {
        lock.lock()
        defer { lock.unlock() }

        startTime = time
        wallClockStart = CACurrentMediaTime()
        pauseTime = .zero
        isPlaying = true
    }

    /// Pause the clock
    public func pause() {
        lock.lock()
        defer { lock.unlock() }

        if isPlaying {
            pauseTime = currentTime
            isPlaying = false
        }
    }

    /// Resume the clock
    public func resume() {
        lock.lock()
        defer { lock.unlock() }

        if !isPlaying {
            // Reset wall clock start to now, keeping the same video position
            wallClockStart = CACurrentMediaTime()
            startTime = pauseTime
            isPlaying = true
        }
    }

    /// Get current time (video position)
    public var currentTime: CMTime {
        lock.lock()
        defer { lock.unlock() }

        if !isPlaying {
            return pauseTime
        }

        // Calculate elapsed time since playback started
        let elapsed = CACurrentMediaTime() - wallClockStart
        return CMTimeAdd(startTime, CMTime(seconds: elapsed, preferredTimescale: 1000000000))
    }

    /// Get current time in seconds
    public var currentTimeSeconds: Double {
        return currentTime.seconds
    }

    /// Reset the clock
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        startTime = .zero
        wallClockStart = 0
        pauseTime = .zero
        isPlaying = false
    }

    /// Set clock to a specific time (used after seek)
    public func setTime(_ time: CMTime) {
        lock.lock()
        defer { lock.unlock() }

        if isPlaying {
            // If playing, update start position and reset wall clock
            startTime = time
            wallClockStart = CACurrentMediaTime()
        } else {
            // If paused, just update the pause position
            pauseTime = time
            startTime = time
        }
    }
}
