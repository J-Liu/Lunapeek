// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import CoreAudio
import Foundation

/// FFmpeg-based audio decoder for software decoding.
/// This is a placeholder implementation until FFmpeg is integrated.
public final class FFmpegAudioDecoderPlugin: AudioDecoderPlugin {
    private var isConfigured = false
    private var currentCodec: String?

    public init() {}

    public func configure(with formatDescription: MediaFormatDescription) async throws {
        currentCodec = formatDescription.codecName
        isConfigured = true

        // TODO: Implement with FFmpeg avcodec_find_decoder and avcodec_open2
    }

    public func decode(packet: MediaPacket) async throws -> AudioSamples? {
        guard isConfigured else {
            throw AudioDecoderError.notConfigured
        }

        // TODO: Implement with FFmpeg avcodec_send_packet / avcodec_receive_frame
        return nil
    }

    public func flush() async throws -> AudioSamples? {
        guard isConfigured else {
            return nil
        }

        // TODO: Implement with FFmpeg avcodec_send_packet(NULL) to drain
        return nil
    }

    public func reset() async {
        // TODO: Implement with FFmpeg avcodec_close and avcodec_free_context
        isConfigured = false
        currentCodec = nil
    }

    public static func supports(codec: String) -> Bool {
        // FFmpeg supports a wide range of audio codecs
        let supportedCodecs = [
            "aac", "mp4a", "aac-lc", "he-aac",
            "mp3", "mp2",
            "flac",
            "vorbis", "opus",
            "ac3", "eac3", "dts", "dts-hd",
            "pcm", "wav",
            "alac", "ape", "wv"
        ]
        return supportedCodecs.contains(codec.lowercased())
    }
}
