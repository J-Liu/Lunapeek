// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Video renderer using AVSampleBufferDisplayLayer for hardware-accelerated display
public final class LPVideoRenderer {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let frameQueue = LPFrameQueue<LPVideoFrame>(maxSize: 30)
    private var isConfigured = false

    // Playback state
    private var _isPlaying = false
    private let lock = NSLock()
    private var isPlaying: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isPlaying }
        set { lock.lock(); defer { lock.unlock() }; _isPlaying = newValue }
    }

    // Audio clock reference for synchronization
    private weak var audioClock: LPAudioClock?

    // Video clock for when there's no audio
    private var videoClockStartTime: Double = 0  // Wall clock when playback started
    private var videoClockBase: CMTime = .zero   // Video position at start
    private var displayQueue: DispatchQueue?

    // Current time tracking
    private var _currentTime: CMTime = .zero
    public var currentTime: CMTime {
        lock.lock(); defer { lock.unlock() }; return _currentTime
    }

    public init() {
        setupDisplayLayer()
    }

    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    /// The layer to add to your view hierarchy
    public var layer: CALayer {
        displayLayer
    }

    /// Set audio clock for synchronization
    public func setAudioClock(_ clock: LPAudioClock) {
        audioClock = clock
    }

    /// Start playback - begin display loop
    public func play() {
        guard !isPlaying else { return }
        isPlaying = true

        // Initialize video clock
        videoClockStartTime = CACurrentMediaTime()

        // Start display loop
        displayQueue = DispatchQueue(label: "com.lunapeek.videoDisplay", qos: .userInteractive)
        displayQueue?.async { [weak self] in
            self?.displayLoop()
        }
    }

    /// Pause playback - stop display loop
    public func pause() {
        isPlaying = false
        displayQueue = nil
    }

    /// Get current playback time - use audio clock if available, otherwise video clock
    private func getPlaybackTime() -> CMTime {
        if let audioClock = audioClock {
            return audioClock.currentTime
        }

        // Fallback to video clock
        let elapsed = CACurrentMediaTime() - videoClockStartTime
        return CMTimeAdd(videoClockBase, CMTime(seconds: elapsed, preferredTimescale: 1000000000))
    }

    /// Set video clock base time (after seek)
    public func setVideoClockBase(_ time: CMTime) {
        videoClockBase = time
        videoClockStartTime = CACurrentMediaTime()
    }

    /// Display loop - show frames at correct time
    private func displayLoop() {
        while isPlaying {
            // Get next frame
            guard let frame = frameQueue.peek() else {
                // No frame available, wait a bit
                Thread.sleep(forTimeInterval: 0.001)
                continue
            }

            // Check if it's time to display this frame
            let framePts = frame.pts

            // Get current playback time
            let playbackTime = getPlaybackTime()

            // Calculate wait time
            let diff = CMTimeSubtract(framePts, playbackTime)
            let waitSeconds = diff.seconds

            if waitSeconds > 0.020 {
                // Frame is in the future, wait a bit
                Thread.sleep(forTimeInterval: min(waitSeconds * 0.5, 0.010))
                continue
            }

            // Frame is due (or late) - display it
            _ = frameQueue.pop(wait: false)
            displayFrame(frame)

            // Update current time
            lock.lock()
            _currentTime = framePts
            lock.unlock()
        }
    }

    /// Display a frame
    private func displayFrame(_ frame: LPVideoFrame) {
        guard let pixelBuffer = frame.pixelBuffer else {
            debugLog("⚠️ VideoRenderer: frame has no pixelBuffer")
            return
        }

        var sampleBuffer: CMSampleBuffer?

        // Create format description from pixel buffer
        var formatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )

        guard status == noErr, let formatDesc = formatDesc else {
            debugLog("❌ VideoRenderer: failed to create format description, status=\(status)")
            return
        }

        // Use the CMTime from frame directly
        var timingInfo = CMSampleTimingInfo(
            duration: frame.duration,
            presentationTimeStamp: frame.pts,
            decodeTimeStamp: .invalid
        )

        // Create sample buffer
        let sampleStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sampleBuffer = sampleBuffer else {
            debugLog("❌ VideoRenderer: failed to create sample buffer, status=\(sampleStatus)")
            return
        }

        // Enqueue for display - AVSampleBufferDisplayLayer will handle timing based on pts
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
        isConfigured = true
    }

    /// Enqueue a decoded video frame for display
    public func enqueue(_ frame: LPVideoFrame) {
        frameQueue.push(frame)
    }

    /// Flush all pending frames
    public func flush() {
        frameQueue.flush()
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: false, completionHandler: nil)
    }

    /// Reset the renderer
    public func reset() {
        flush()
        isConfigured = false
        isPlaying = false
        displayQueue = nil
        videoClockBase = .zero
    }

    /// Check if renderer has error
    public var hasError: Bool {
        return displayLayer.status == .failed
    }
}
