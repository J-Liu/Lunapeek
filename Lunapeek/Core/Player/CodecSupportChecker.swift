// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import FFmpegBridge

/// Result of checking codec support
public struct CodecSupportResult {
    public let needsFFmpeg: Bool
    public let reason: String?

    public static func supported() -> CodecSupportResult {
        return CodecSupportResult(needsFFmpeg: false, reason: nil)
    }

    public static func needsFFmpeg(reason: String) -> CodecSupportResult {
        return CodecSupportResult(needsFFmpeg: true, reason: reason)
    }
}

/// Checks if codecs are supported by iOS AVPlayer
public struct CodecSupportChecker {

    /// Check if a video codec is supported by AVPlayer
    public static func isVideoCodecSupported(_ codecId: AVCodecID, codecParams: UnsafeMutablePointer<AVCodecParameters>?) -> CodecSupportResult {
        switch codecId {
        case AV_CODEC_ID_H264:
            // H.264 is fully supported
            return .supported()

        case AV_CODEC_ID_HEVC:
            // HEVC is supported, but 10-bit is NOT
            if let params = codecParams {
                let profile = params.pointee.profile
                let bitDepth = params.pointee.bits_per_coded_sample

                // Check for 10-bit (profile 2 or bit depth > 8)
                if profile == 2 || bitDepth > 8 {
                    return .needsFFmpeg(reason: "10-bit HEVC not supported by hardware decoder")
                }
            }
            return .supported()

        case AV_CODEC_ID_VP9:
            // VP9 requires FFmpeg
            return .needsFFmpeg(reason: "VP9 not supported by AVPlayer")

        case AV_CODEC_ID_AV1:
            // AV1 requires FFmpeg
            return .needsFFmpeg(reason: "AV1 not supported by AVPlayer")

        case AV_CODEC_ID_MPEG2VIDEO, AV_CODEC_ID_MPEG4:
            // MPEG-2 and MPEG-4 are partially supported
            return .supported()

        case AV_CODEC_ID_VC1:
            // VC-1 requires FFmpeg
            return .needsFFmpeg(reason: "VC-1 not supported by AVPlayer")

        default:
            // Unknown video codec - needs FFmpeg
            return .needsFFmpeg(reason: "Unknown video codec: \(codecId.rawValue)")
        }
    }

    /// Check if an audio codec is supported by AVPlayer
    public static func isAudioCodecSupported(_ codecId: AVCodecID) -> CodecSupportResult {
        switch codecId {
        case AV_CODEC_ID_AAC, AV_CODEC_ID_AAC_LATM:
            // AAC is fully supported
            return .supported()

        case AV_CODEC_ID_MP3:
            // MP3 is supported
            return .supported()

        case AV_CODEC_ID_AC3:
            // AC-3 is supported (Dolby Digital)
            return .supported()

        case AV_CODEC_ID_EAC3:
            // E-AC-3 (Dolby Digital Plus) requires FFmpeg
            return .needsFFmpeg(reason: "E-AC-3 audio not supported by AVPlayer")

        case AV_CODEC_ID_DTS:
            // DTS and all its variants require FFmpeg
            return .needsFFmpeg(reason: "DTS audio not supported by AVPlayer")

        case AV_CODEC_ID_TRUEHD:
            // TrueHD requires FFmpeg
            return .needsFFmpeg(reason: "TrueHD audio not supported by AVPlayer")

        case AV_CODEC_ID_FLAC:
            // FLAC requires FFmpeg
            return .needsFFmpeg(reason: "FLAC audio not supported by AVPlayer")

        case AV_CODEC_ID_OPUS:
            // Opus requires FFmpeg
            return .needsFFmpeg(reason: "Opus audio not supported by AVPlayer")

        case AV_CODEC_ID_VORBIS:
            // Vorbis requires FFmpeg
            return .needsFFmpeg(reason: "Vorbis audio not supported by AVPlayer")

        case AV_CODEC_ID_PCM_S16LE, AV_CODEC_ID_PCM_S16BE,
             AV_CODEC_ID_PCM_U8, AV_CODEC_ID_PCM_S24LE,
             AV_CODEC_ID_PCM_S24BE, AV_CODEC_ID_PCM_S32LE,
             AV_CODEC_ID_PCM_S32BE, AV_CODEC_ID_PCM_F32LE,
             AV_CODEC_ID_PCM_F32BE:
            // PCM variants are supported
            return .supported()

        case AV_CODEC_ID_ALAC:
            // ALAC is supported
            return .supported()

        default:
            // Unknown audio codec - needs FFmpeg
            return .needsFFmpeg(reason: "Unknown audio codec: \(codecId.rawValue)")
        }
    }

    /// Check all streams in a file and determine if FFmpeg decoding is needed
    public static func checkFile(_ url: URL) async -> CodecSupportResult {
        // Quick check by extension
        let ext = url.pathExtension.lowercased()

        // MP4/MOV/M4V files are likely to be supported
        if ["mp4", "mov", "m4v", "3gp"].contains(ext) {
            // But we still need to check for specific codecs
        }

        // Use FFmpeg to probe the file
        var formatContext: UnsafeMutablePointer<AVFormatContext>?
        let result = avformat_open_input(&formatContext, url.path, nil, nil)

        guard result == 0, let ctx = formatContext else {
            return .needsFFmpeg(reason: "Failed to open file for codec detection")
        }

        defer {
            var ctxPtr: UnsafeMutablePointer<AVFormatContext>? = ctx
            avformat_close_input(&ctxPtr)
        }

        // Find stream info
        let infoResult = avformat_find_stream_info(ctx, nil)
        guard infoResult >= 0 else {
            return .needsFFmpeg(reason: "Failed to find stream info")
        }

        // Check each stream
        let nbStreams = Int(ctx.pointee.nb_streams)

        for i in 0..<nbStreams {
            guard let stream = ctx.pointee.streams.advanced(by: i).pointee,
                  let codecParams = stream.pointee.codecpar else {
                continue
            }

            let codecId = codecParams.pointee.codec_id
            let codecType = codecParams.pointee.codec_type

            if codecType == AVMEDIA_TYPE_VIDEO {
                let result = isVideoCodecSupported(codecId, codecParams: codecParams)
                if result.needsFFmpeg {
                    return result
                }
            } else if codecType == AVMEDIA_TYPE_AUDIO {
                let result = isAudioCodecSupported(codecId)
                if result.needsFFmpeg {
                    return result
                }
            }
        }

        return .supported()
    }
}
