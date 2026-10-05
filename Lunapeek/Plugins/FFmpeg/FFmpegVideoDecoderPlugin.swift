// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import CoreVideo
import Foundation

/// FFmpeg-based video decoder for software decoding.
/// This is a placeholder implementation until FFmpeg is integrated.
public final class FFmpegVideoDecoderPlugin: VideoDecoderPlugin {
    private var isConfigured = false
    private var currentCodec: String?

    public init() {}

    public func configure(with formatDescription: MediaFormatDescription) async throws {
        currentCodec = formatDescription.codecName
        isConfigured = true

        // TODO: Implement with FFmpeg avcodec_find_decoder and avcodec_open2
    }

    public func decode(packet: MediaPacket) async throws -> [VideoFrame] {
        guard isConfigured else {
            throw VideoDecoderError.notConfigured
        }

        // TODO: Implement with FFmpeg avcodec_send_packet / avcodec_receive_frame
        return []
    }

    public func flush() async throws -> [VideoFrame] {
        guard isConfigured else {
            return []
        }

        // TODO: Implement with FFmpeg avcodec_send_packet(NULL) to drain
        return []
    }

    public func reset() async {
        // TODO: Implement with FFmpeg avcodec_close and avcodec_free_context
        isConfigured = false
        currentCodec = nil
    }

    public static func supports(codec: String) -> Bool {
        // FFmpeg supports a wide range of codecs
        let supportedCodecs = [
            "h264", "avc1", "hvc1", "hev1", "hevc",
            "vp8", "vp9", "av1",
            "mpeg2", "mpeg4",
            "theora", "vc1"
        ]
        return supportedCodecs.contains(codec.lowercased())
    }
}
