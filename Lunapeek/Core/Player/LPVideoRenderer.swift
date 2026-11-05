// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import CoreVideo
import UIKit

/// Video renderer using AVSampleBufferDisplayLayer for hardware-accelerated display
public final class LPVideoRenderer {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var isConfigured = false

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

    /// Enqueue a decoded video frame for display
    public func enqueue(_ frame: LPVideoFrame) {
        guard let pixelBuffer = frame.pixelBuffer else {
            // Software-decoded frames need conversion (not yet supported)
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

        guard status == noErr, let formatDesc = formatDesc else { return }

        // Create timing info
        let pts = CMTime(
            value: frame.pts,
            timescale: 1,
            flags: .valid,
            epoch: 0
        )
        let duration = CMTime(
            value: frame.duration,
            timescale: 1,
            flags: .valid,
            epoch: 0
        )

        var timingInfo = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
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

        guard sampleStatus == noErr, let sampleBuffer = sampleBuffer else { return }

        // Enqueue for display
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
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
    }

    /// Check if renderer has error
    public var hasError: Bool {
        return displayLayer.status == .failed
    }
}
