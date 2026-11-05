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
    private var timebase: CMTimebase?
    private var isConfigured = false

    public init() {
        setupDisplayLayer()
        setupTimebase()
    }

    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    private func setupTimebase() {
        // Create timebase for frame rate control
        var timebase: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if status == noErr, let timebase = timebase {
            self.timebase = timebase
            CMTimebaseSetRate(timebase, rate: 1.0)
            CMTimebaseSetTime(timebase, time: .zero)
            debugLog("✅ VideoRenderer: timebase created")
        } else {
            debugLog("❌ VideoRenderer: failed to create timebase, status=\(status)")
        }
    }

    /// The layer to add to your view hierarchy
    public var layer: CALayer {
        displayLayer
    }

    /// Start playback (set timebase rate to 1.0)
    public func play() {
        if let timebase = timebase {
            CMTimebaseSetRate(timebase, rate: 1.0)
            debugLog("🔊 VideoRenderer: timebase rate set to 1.0")
        }
    }

    /// Pause playback (set timebase rate to 0)
    public func pause() {
        if let timebase = timebase {
            CMTimebaseSetRate(timebase, rate: 0)
            debugLog("🔊 VideoRenderer: timebase rate set to 0")
        }
    }

    /// Enqueue a decoded video frame for display
    public func enqueue(_ frame: LPVideoFrame) {
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

        // Set timebase on sample buffer if available
        if let timebase = timebase {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
            if let attachments = attachments {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                // Set timebase using CFString key
                let timebaseKey = "Timebase" as CFString
                CFDictionarySetValue(dict, Unmanaged.passUnretained(timebaseKey).toOpaque(), Unmanaged.passUnretained(timebase).toOpaque())
            }
        }

        // Enqueue for display
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
        debugLog("✅ VideoRenderer: enqueued frame, pts=\(frame.pts.seconds)")
        isConfigured = true
    }

    /// Flush all pending frames
    public func flush() {
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: false, completionHandler: nil)
    }

    /// Reset the renderer
    public func reset() {
        flush()
        isConfigured = false
        // Reset timebase
        if let timebase = timebase {
            CMTimebaseSetTime(timebase, time: .zero)
        }
    }

    /// Check if renderer has error
    public var hasError: Bool {
        return displayLayer.status == .failed
    }
}
