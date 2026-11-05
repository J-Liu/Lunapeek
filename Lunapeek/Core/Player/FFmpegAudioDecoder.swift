// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import CoreAudio
import FFmpegBridge

/// Software audio decoder using FFmpeg libavcodec
/// Supports formats not supported by AudioToolbox (E-AC-3, DTS, FLAC, Opus, etc.)
public final class FFmpegAudioDecoder: LPAudioDecoderProtocol {
    public var timebase: AVRational = AVRational(num: 1, den: 1)
    public var onAudioDecoded: ((LPAudioFrame) -> Void)?

    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var swrContext: OpaquePointer?

    // Output format (stereo, 16-bit PCM, 44100Hz)
    private let outSampleRate: Int32 = 44100
    private let outChannels: Int32 = 2
    private let outSampleFormat = AV_SAMPLE_FMT_S16

    public init() {}

    public func open(codecParams: UnsafeMutablePointer<AVCodecParameters>, streamIndex: Int) -> Bool {
        let codecId = codecParams.pointee.codec_id

        // Find decoder
        guard let codec = avcodec_find_decoder(codecId) else {
            debugLog("❌ FFmpegAudio: Decoder not found for codec \(codecId.rawValue)")
            return false
        }

        // Allocate context
        guard let context = avcodec_alloc_context3(codec) else {
            debugLog("❌ FFmpegAudio: Failed to allocate context")
            return false
        }

        codecContext = context

        // Copy codec parameters
        guard avcodec_parameters_to_context(context, codecParams) >= 0 else {
            debugLog("❌ FFmpegAudio: Failed to copy parameters")
            close()
            return false
        }

        // Open decoder
        guard avcodec_open2(context, codec, nil) >= 0 else {
            debugLog("❌ FFmpegAudio: Failed to open codec")
            close()
            return false
        }

        // Allocate frame
        guard let frame = av_frame_alloc() else {
            debugLog("❌ FFmpegAudio: Failed to allocate frame")
            close()
            return false
        }
        self.frame = frame

        // Create swresample context for format conversion
        let inSampleRate = context.pointee.sample_rate
        let inChannels = context.pointee.ch_layout.nb_channels
        let inSampleFormat = context.pointee.sample_fmt

        swrContext = swr_alloc()
        guard let swrContext = swrContext else {
            debugLog("❌ FFmpegAudio: Failed to allocate swresample")
            close()
            return false
        }

        // Set input options (cast OpaquePointer to UnsafeMutableRawPointer)
        let swrPtr = UnsafeMutableRawPointer(swrContext)
        var inLayout = context.pointee.ch_layout
        av_opt_set_chlayout(swrPtr, "in_chlayout", &inLayout, 0)
        av_opt_set_int(swrPtr, "in_sample_rate", Int64(inSampleRate), 0)
        av_opt_set_sample_fmt(swrPtr, "in_sample_fmt", inSampleFormat, 0)

        // Set output options (stereo, 16-bit PCM, 44100Hz)
        var outLayout = AVChannelLayout()
        av_channel_layout_default(&outLayout, outChannels)
        av_opt_set_chlayout(swrPtr, "out_chlayout", &outLayout, 0)
        av_opt_set_int(swrPtr, "out_sample_rate", Int64(outSampleRate), 0)
        av_opt_set_sample_fmt(swrPtr, "out_sample_fmt", outSampleFormat, 0)

        // Initialize
        guard swr_init(swrContext) >= 0 else {
            debugLog("❌ FFmpegAudio: Failed to init swresample")
            close()
            return false
        }

        debugLog("✅ FFmpegAudio: Decoder opened for \(codecId.rawValue), \(inSampleRate)Hz, \(inChannels)ch -> \(outSampleRate)Hz, \(outChannels)ch")
        return true
    }

    public func decode(packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        guard let context = codecContext, let frame = frame, swrContext != nil else {
            return false
        }

        // Send packet to decoder
        let pkt: UnsafeMutablePointer<AVPacket>? = packet
        let sendRet = avcodec_send_packet(context, pkt)
        if sendRet < 0 && sendRet != AVERROR_EOF {
            if sendRet != -11 && sendRet != -35 {
                debugLog("❌ FFmpegAudio: send_packet error: \(sendRet)")
            }
        }

        // Receive decoded frames
        var frameCount = 0
        let maxFrames = 4

        while frameCount < maxFrames {
            let receiveRet = avcodec_receive_frame(context, frame)

            if receiveRet < 0 {
                if receiveRet != -11 && receiveRet != -35 && receiveRet != AVERROR_EOF {
                    debugLog("❌ FFmpegAudio: receive_frame error: \(receiveRet)")
                }
                break
            }

            frameCount += 1

            // Convert to output format
            if let audioFrame = convertFrame(frame) {
                onAudioDecoded?(audioFrame)
            }

            av_frame_unref(frame)
        }

        return true
    }

    public func flush() {
        guard let context = codecContext, let frame = frame else { return }

        avcodec_send_packet(context, nil)

        while true {
            let ret = avcodec_receive_frame(context, frame)
            if ret < 0 { break }

            if let audioFrame = convertFrame(frame) {
                onAudioDecoded?(audioFrame)
            }
            av_frame_unref(frame)
        }
    }

    public func close() {
        if let frame = frame {
            var framePtr: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&framePtr)
            self.frame = nil
        }

        if swrContext != nil {
            var swrPtr = swrContext
            swr_free(&swrPtr)
            self.swrContext = nil
        }

        if let context = codecContext {
            var ctxPtr: UnsafeMutablePointer<AVCodecContext>? = context
            avcodec_free_context(&ctxPtr)
            self.codecContext = nil
        }

        debugLog("✅ FFmpegAudio: Closed")
    }

    // MARK: - Private

    private func convertFrame(_ frame: UnsafeMutablePointer<AVFrame>) -> LPAudioFrame? {
        guard let swrContext = swrContext else { return nil }

        // Calculate output buffer size
        let inSamples = frame.pointee.nb_samples
        let outSamples = swr_get_out_samples(swrContext, inSamples)
        let outSize = Int(outSamples) * Int(outChannels) * 2  // 2 bytes per sample (16-bit)

        // Allocate output buffer
        var outBuffer = [UInt8](repeating: 0, count: outSize)

        // Convert
        let converted = outBuffer.withUnsafeMutableBytes { buffer in
            guard let baseAddr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-1)
            }

            var outDataPtr: UnsafeMutablePointer<UInt8>? = baseAddr

            // Create array of pointers for input data
            let inData = frame.pointee.data
            return withUnsafePointer(to: inData) { inDataPtr in
                let inDataArray = inDataPtr.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: 8) {
                    $0
                }
                return swr_convert(
                    swrContext,
                    &outDataPtr,
                    Int32(outSamples),
                    inDataArray,
                    inSamples
                )
            }
        }

        guard converted >= 0 else {
            debugLog("❌ FFmpegAudio: swr_convert failed: \(converted)")
            return nil
        }

        let actualSamples = Int(converted)
        let actualSize = actualSamples * Int(outChannels) * 2

        // Create audio frame
        return LPAudioFrame(
            data: Data(outBuffer.prefix(actualSize)),
            pts: frame.pointee.pts,
            duration: frame.pointee.duration,
            sampleRate: outSampleRate,
            channels: outChannels,
            format: outSampleFormat
        )
    }

    private var AVERROR_EOF: Int32 { -541478725 }
}
