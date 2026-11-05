// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import CoreVideo
import FFmpegBridge

/// Video frame decoded by hardware or software decoder
public final class LPVideoFrame {
    public let pixelBuffer: CVPixelBuffer?
    public let pts: Int64
    public let duration: Int64
    public let isSync: Bool  // Keyframe

    // For software decoding (FFmpeg)
    public let yuvData: Data?
    public let width: Int32
    public let height: Int32
    public let format: AVPixelFormat

    public init(pixelBuffer: CVPixelBuffer, pts: Int64, duration: Int64, isSync: Bool) {
        self.pixelBuffer = pixelBuffer
        self.pts = pts
        self.duration = duration
        self.isSync = isSync
        self.yuvData = nil
        self.width = 0
        self.height = 0
        self.format = AV_PIX_FMT_NONE
    }

    public init(yuvData: Data, width: Int32, height: Int32, format: AVPixelFormat, pts: Int64, duration: Int64, isSync: Bool) {
        self.pixelBuffer = nil
        self.pts = pts
        self.duration = duration
        self.isSync = isSync
        self.yuvData = yuvData
        self.width = width
        self.height = height
        self.format = format
    }
}

/// Audio frame decoded by decoder
public final class LPAudioFrame {
    public let data: Data
    public let pts: Int64
    public let duration: Int64
    public let sampleRate: Int32
    public let channels: Int32
    public let format: AVSampleFormat

    public init(data: Data, pts: Int64, duration: Int64, sampleRate: Int32, channels: Int32, format: AVSampleFormat) {
        self.data = data
        self.pts = pts
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
    }
}
