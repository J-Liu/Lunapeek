// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import CoreVideo
import UIKit

/// Video renderer using AVSampleBufferDisplayLayer.
public final class VideoRenderer {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var isConfigured = false

    public init() {
        setupDisplayLayer()
    }

    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    public var layer: CALayer {
        displayLayer
    }

    public func configure(with formatDescription: MediaFormatDescription?) {
        guard let videoProps = formatDescription?.videoProperties else { return }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: videoProps.width,
            kCVPixelBufferHeightKey as String: videoProps.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferOpenGLCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var formatDesc: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            dimensions: CGSize(width: CGFloat(videoProps.width), height: CGFloat(videoProps.height)),
            extensions: attributes as CFDictionary,
            formatDescriptionOut: &formatDesc
        )

        isConfigured = true
    }

    public func enqueue(_ frame: VideoFrame) {
        var sampleBuffer: CMSampleBuffer?

        let formatDesc = createFormatDescription(for: frame.pixelBuffer)
        let pts = CMTime(
            seconds: Double(frame.presentationTimestamp) / 1_000_000,
            preferredTimescale: 1_000_000
        )
        let duration = CMTime(
            seconds: Double(frame.duration) / 1_000_000,
            preferredTimescale: 1_000_000
        )

        var timingInfo = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer = sampleBuffer else {
            return
        }

        displayLayer.enqueue(sampleBuffer)
    }

    private func createFormatDescription(for pixelBuffer: CVPixelBuffer) -> CMFormatDescription? {
        var formatDesc: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        return formatDesc
    }

    public func flush() {
        displayLayer.flushAndRemoveImage()
    }

    public func reset() {
        flush()
        isConfigured = false
    }
}
