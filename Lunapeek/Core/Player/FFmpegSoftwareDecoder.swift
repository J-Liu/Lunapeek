// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import CoreMedia
import CoreVideo
import FFmpegBridge

/// Software video decoder using FFmpeg libavcodec
/// Supports formats not supported by VideoToolbox (10-bit HEVC, VP9, etc.)
public final class FFmpegSoftwareDecoder: LPVideoDecoderProtocol {
    public var timebase: AVRational = AVRational(num: 1, den: 1)
    public var onFrameDecoded: ((LPVideoFrame) -> Void)?

    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var swsContext: UnsafeMutablePointer<SwsContext>?
    private var dstFrame: UnsafeMutablePointer<AVFrame>?
    private var lastWidth: Int32 = 0
    private var lastHeight: Int32 = 0
    private var lastFormat: AVPixelFormat = AV_PIX_FMT_NONE
    private let lock = NSLock()

    public init() {}

    public func open(codecParams: UnsafeMutablePointer<AVCodecParameters>, streamIndex: Int) -> Bool {
        let codecId = codecParams.pointee.codec_id

        // Find decoder
        guard let codec = avcodec_find_decoder(codecId) else {
            debugLog("❌ FFmpegSoft: Decoder not found for codec \(codecId.rawValue)")
            return false
        }

        // Allocate context
        guard let context = avcodec_alloc_context3(codec) else {
            debugLog("❌ FFmpegSoft: Failed to allocate context")
            return false
        }

        codecContext = context

        // Copy codec parameters
        guard avcodec_parameters_to_context(context, codecParams) >= 0 else {
            debugLog("❌ FFmpegSoft: Failed to copy parameters")
            close()
            return false
        }

        // Open decoder
        guard avcodec_open2(context, codec, nil) >= 0 else {
            debugLog("❌ FFmpegSoft: Failed to open codec")
            close()
            return false
        }

        // Allocate frame
        guard let frame = av_frame_alloc() else {
            debugLog("❌ FFmpegSoft: Failed to allocate frame")
            close()
            return false
        }
        self.frame = frame

        debugLog("✅ FFmpegSoft: Decoder opened for \(codecId.rawValue), \(context.pointee.width)x\(context.pointee.height)")
        return true
    }

    public func decode(packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let context = codecContext, let frame = frame else {
            debugLog("❌ FFmpegSoft: decode called but no context/frame, context=\(codecContext != nil), frame=\(self.frame != nil)")
            return false
        }

        // Check if decoder is still valid
        guard context.pointee.codec != nil else {
            debugLog("❌ FFmpegSoft: codec is nil after flush")
            return false
        }

        debugLog("🔄 FFmpegSoft: decode called, pts=\(packet.pointee.pts), size=\(packet.pointee.size)")

        // Send packet to decoder
        let pkt: UnsafeMutablePointer<AVPacket>? = packet
        let sendRet = avcodec_send_packet(context, pkt)
        if sendRet < 0 && sendRet != AVERROR_EOF {
            // -11 (EAGAIN) or -35 means need to read output first
            if sendRet != -11 && sendRet != -35 {
                debugLog("❌ FFmpegSoft: send_packet error: \(sendRet), size=\(packet.pointee.size), pts=\(packet.pointee.pts)")
                return false
            } else {
                debugLog("⚠️ FFmpegSoft: send_packet EAGAIN, need to receive frames first")
            }
        }

        // Receive decoded frames (may be multiple for B-frames)
        var frameCount = 0
        let maxFrames = 4  // Limit frames per packet to prevent infinite loops

        while frameCount < maxFrames {
            let receiveRet = avcodec_receive_frame(context, frame)

            if receiveRet < 0 {
                // -11 (EAGAIN) or -35 means need more input data
                if receiveRet != -11 && receiveRet != -35 && receiveRet != AVERROR_EOF {
                    debugLog("❌ FFmpegSoft: receive_frame error: \(receiveRet)")
                } else if receiveRet == -11 || receiveRet == -35 {
                    debugLog("⚠️ FFmpegSoft: receive_frame EAGAIN, need more packets")
                }
                break  // Exit loop on any error
            }

            frameCount += 1

            // Convert frame to output format and deliver
            if let outputFrame = convertFrame(frame) {
                debugLog("✅ FFmpegSoft: Frame decoded, pts=\(outputFrame.pts)")
                onFrameDecoded?(outputFrame)
            }

            av_frame_unref(frame)
        }

        return frameCount > 0
    }

    public func flush() {
        lock.lock()
        defer { lock.unlock() }

        debugLog("🔄 FFmpegSoft: flush() called")

        guard let context = codecContext else {
            debugLog("⚠️ FFmpegSoft: flush() - no codecContext")
            return
        }

        // Use avcodec_flush_buffers to properly reset the decoder
        // This is the correct way to flush after seek
        avcodec_flush_buffers(context)

        debugLog("✅ FFmpegSoft: flush() complete, codecContext=\(codecContext != nil), frame=\(self.frame != nil)")

        // Reset swsContext to force recreation after seek
        if let swsContext = swsContext {
            sws_freeContext(swsContext)
            self.swsContext = nil
        }
        if let dstFrame = dstFrame {
            var dstPtr: UnsafeMutablePointer<AVFrame>? = dstFrame
            av_frame_free(&dstPtr)
            self.dstFrame = nil
        }
        lastWidth = 0
        lastHeight = 0
        lastFormat = AV_PIX_FMT_NONE
    }

    public func close() {
        if let frame = frame {
            var framePtr: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&framePtr)
            self.frame = nil
        }

        if let dstFrame = dstFrame {
            var dstPtr: UnsafeMutablePointer<AVFrame>? = dstFrame
            av_frame_free(&dstPtr)
            self.dstFrame = nil
        }

        if let swsContext = swsContext {
            sws_freeContext(swsContext)
            self.swsContext = nil
        }

        if let context = codecContext {
            var ctxPtr: UnsafeMutablePointer<AVCodecContext>? = context
            avcodec_free_context(&ctxPtr)
            self.codecContext = nil
        }

        lastWidth = 0
        lastHeight = 0
        lastFormat = AV_PIX_FMT_NONE

        debugLog("✅ FFmpegSoft: Closed")
    }

    // MARK: - Private

    private func convertFrame(_ frame: UnsafeMutablePointer<AVFrame>) -> LPVideoFrame? {
        let width = frame.pointee.width
        let height = frame.pointee.height
        let format = AVPixelFormat(frame.pointee.format)

        // Check if we need swscale conversion (not NV12)
        let needsConversion = format != AV_PIX_FMT_NV12

        var srcFrame = frame

        if needsConversion {
            // Setup swscale context if needed
            if width != lastWidth || height != lastHeight || format != lastFormat {
                // Free old context
                if let swsContext = swsContext {
                    sws_freeContext(swsContext)
                }
                if let dstFrame = dstFrame {
                    var dstPtr: UnsafeMutablePointer<AVFrame>? = dstFrame
                    av_frame_free(&dstPtr)
                }

                // Create new swscale context for NV12 output
                // SWS_BILINEAR = 4
                swsContext = sws_getContext(
                    width, height, format,
                    width, height, AV_PIX_FMT_NV12,
                    4, nil, nil, nil
                )

                // Allocate destination frame
                dstFrame = av_frame_alloc()
                if let dstFrame = dstFrame {
                    dstFrame.pointee.width = width
                    dstFrame.pointee.height = height
                    dstFrame.pointee.format = Int32(AV_PIX_FMT_NV12.rawValue)
                    av_frame_get_buffer(dstFrame, 0)
                }

                lastWidth = width
                lastHeight = height
                lastFormat = format
            }

            // Convert frame to NV12
            guard let swsContext = swsContext, let dstFrame = dstFrame else {
                debugLog("❌ FFmpegSoft: Failed to create swscale context")
                return nil
            }

            // Prepare source data pointers
            let srcData = frame.pointee.data
            let srcLinesize = frame.pointee.linesize

            // Convert using sws_scale
            withUnsafePointer(to: srcData) { srcDataPtr in
                srcDataPtr.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: 8) { srcDataArray in
                    withUnsafePointer(to: srcLinesize) { srcLinesizePtr in
                        srcLinesizePtr.withMemoryRebound(to: Int32.self, capacity: 8) { srcLinesizeArray in
                            let dstData = dstFrame.pointee.data
                            let dstLinesize = dstFrame.pointee.linesize

                            withUnsafePointer(to: dstData) { dstDataPtr in
                                dstDataPtr.withMemoryRebound(to: UnsafeMutablePointer<UInt8>?.self, capacity: 8) { dstDataArray in
                                    withUnsafePointer(to: dstLinesize) { dstLinesizePtr in
                                        dstLinesizePtr.withMemoryRebound(to: Int32.self, capacity: 8) { dstLinesizeArray in
                                            _ = sws_scale(
                                                swsContext,
                                                srcDataArray,
                                                srcLinesizeArray,
                                                0, height,
                                                dstDataArray,
                                                dstLinesizeArray
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            srcFrame = dstFrame
        }

        // Create CVPixelBuffer from the frame
        guard let pixelBuffer = createPixelBufferFromFrame(srcFrame, width: Int(width), height: Int(height)) else {
            debugLog("❌ FFmpegSoft: Failed to create pixel buffer")
            return nil
        }

        let ptsValue = frame.pointee.pts != AV_NOPTS_VALUE ? frame.pointee.pts : frame.pointee.best_effort_timestamp
        let durationValue = frame.pointee.duration

        // Convert to CMTime using timebase
        // pts is in stream timebase units, convert to seconds then to CMTime
        let ptsSeconds = Double(ptsValue) * Double(timebase.num) / Double(timebase.den)
        let durationSeconds = Double(durationValue) * Double(timebase.num) / Double(timebase.den)
        let pts = CMTime(seconds: ptsSeconds, preferredTimescale: 600)
        let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)

        // Check keyframe
        let isKeyframe = (Int32(frame.pointee.flags) & AV_FRAME_FLAG_KEY) != 0

        return LPVideoFrame(
            pixelBuffer: pixelBuffer,
            pts: pts,
            duration: duration,
            isSync: isKeyframe
        )
    }

    private func createPixelBufferFromFrame(
        _ frame: UnsafeMutablePointer<AVFrame>,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        // Create NV12 pixel buffer
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        // Copy Y plane
        if let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
           let srcY = frame.pointee.data.0 {
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let srcYStride = Int(frame.pointee.linesize.0)

            for row in 0..<height {
                memcpy(
                    yPlane.advanced(by: row * yStride),
                    srcY.advanced(by: row * srcYStride),
                    min(width, yStride)
                )
            }
        }

        // Copy UV plane (NV12 interleaved)
        if let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1),
           let srcUV = frame.pointee.data.1 {
            let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let srcUVStride = Int(frame.pointee.linesize.1)
            let uvHeight = height / 2

            for row in 0..<uvHeight {
                memcpy(
                    uvPlane.advanced(by: row * uvStride),
                    srcUV.advanced(by: row * srcUVStride),
                    min(width, uvStride)
                )
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }

    private var AVERROR_EOF: Int32 { -541478725 }
    private var AV_NOPTS_VALUE: Int64 { Int64.min }
}
