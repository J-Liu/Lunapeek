// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation
import CoreVideo

/// Represents a decoded video frame.
public struct VideoFrame {
    public let pixelBuffer: CVPixelBuffer
    public let presentationTimestamp: Int64
    public let duration: Int64

    public init(pixelBuffer: CVPixelBuffer, presentationTimestamp: Int64, duration: Int64 = 0) {
        self.pixelBuffer = pixelBuffer
        self.presentationTimestamp = presentationTimestamp
        self.duration = duration
    }
}

/// Video decoder error types.
public enum VideoDecoderError: Error {
    case notConfigured
    case configurationFailed(Error?)
    case decodingFailed(Error?)
    case unsupportedFormat
    case endOfStream
}

/// Video decoder plugin protocol - responsible for decoding video packets.
public protocol VideoDecoderPlugin {
    /// Configures the decoder with the given format description.
    func configure(with formatDescription: MediaFormatDescription) async throws

    /// Decodes a video packet and returns decoded frames.
    /// May return multiple frames for a single packet (B-frames reordering).
    func decode(packet: MediaPacket) async throws -> [VideoFrame]

    /// Flushes any buffered frames.
    func flush() async throws -> [VideoFrame]

    /// Resets the decoder state.
    func reset() async

    /// Returns whether this plugin supports the given codec.
    static func supports(codec: String) -> Bool
}