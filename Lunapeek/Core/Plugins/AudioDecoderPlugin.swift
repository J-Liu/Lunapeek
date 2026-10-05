// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import CoreAudio

/// Represents decoded audio samples.
public struct AudioSamples {
    public let data: Data
    public let sampleCount: Int
    public let presentationTimestamp: Int64
    public let duration: Int64
    public let format: AudioStreamBasicDescription

    public init(
        data: Data,
        sampleCount: Int,
        presentationTimestamp: Int64,
        duration: Int64,
        format: AudioStreamBasicDescription
    ) {
        self.data = data
        self.sampleCount = sampleCount
        self.presentationTimestamp = presentationTimestamp
        self.duration = duration
        self.format = format
    }
}

/// Audio decoder error types.
public enum AudioDecoderError: Error {
    case notConfigured
    case configurationFailed(Error?)
    case decodingFailed(Error?)
    case unsupportedFormat
    case endOfStream
}

/// Audio decoder plugin protocol - responsible for decoding audio packets.
public protocol AudioDecoderPlugin {
    /// Configures the decoder with the given format description.
    func configure(with formatDescription: MediaFormatDescription) async throws

    /// Decodes an audio packet and returns decoded samples.
    func decode(packet: MediaPacket) async throws -> AudioSamples?

    /// Flushes any buffered samples.
    func flush() async throws -> AudioSamples?

    /// Resets the decoder state.
    func reset() async

    /// Returns whether this plugin supports the given codec.
    static func supports(codec: String) -> Bool
}
