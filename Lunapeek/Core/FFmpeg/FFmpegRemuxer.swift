// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import FFmpegBridge

/// Error types for remuxing operations
public enum RemuxerError: Error {
    case failedToOpenInput
    case failedToFindStreamInfo
    case failedToCreateOutput
    case failedToSetupStreams
    case failedToWriteHeader
    case failedToWritePacket
    case invalidStreamIndex
    case cancelled
}

/// Protocol for receiving remuxed data
public protocol RemuxerOutputDelegate: AnyObject {
    func remuxerDidOutputData(_ data: Data)
    func remuxerDidComplete(error: Error?)
}

/// FFmpeg-based remuxer for converting MKV/WebM/AVI/etc to MP4 on-the-fly.
/// Uses avformat API to read input and write MP4 output to a delegate.
public final class FFmpegRemuxer: @unchecked Sendable {
    private var inputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var outputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var streamMapping: [Int: Int] = [:]
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.lunapeek.remuxer", qos: .userInitiated)
    private weak var delegate: RemuxerOutputDelegate?

    public init() {}

    /// Start remuxing from a file URL.
    /// - Parameters:
    ///   - url: Input file URL (local or network)
    ///   - delegate: Delegate to receive remuxed data
    public func start(url: URL, delegate: RemuxerOutputDelegate) {
        self.delegate = delegate

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.remux(url: url)
            } catch {
                self.delegate?.remuxerDidComplete(error: error)
            }
        }
    }

    /// Stop remuxing.
    public func stop() {
        isRunning = false
    }

    // MARK: - Private

    private func remux(url: URL) throws {
        isRunning = true

        // Open input
        var formatContext: UnsafeMutablePointer<AVFormatContext>?
        let inputPath = url.path

        guard avformat_open_input(&formatContext, inputPath, nil, nil) >= 0 else {
            throw RemuxerError.failedToOpenInput
        }

        inputFormatContext = formatContext

        // Retrieve stream info
        guard avformat_find_stream_info(formatContext, nil) >= 0 else {
            cleanup()
            throw RemuxerError.failedToFindStreamInfo
        }

        // Create output format context (MP4)
        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outputContext, nil, "mp4", nil) >= 0 else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

        outputFormatContext = outputContext

        // Setup streams
        guard setupStreams() else {
            cleanup()
            throw RemuxerError.failedToSetupStreams
        }

        // Write header
        guard avformat_write_header(outputContext, nil) >= 0 else {
            cleanup()
            throw RemuxerError.failedToWriteHeader
        }

        // Flush any header data
        flushOutputBuffer()

        // Remux packets
        let packet = av_packet_alloc()
        defer { av_packet_free(&packet) }

        while isRunning {
            let ret = av_read_frame(inputFormatContext, packet)
            if ret < 0 {
                if ret == AVERROR_EOF || ret == -541478725 {
                    break
                }
                continue
            }

            let inStreamIndex = Int(packet!.pointee.stream_index)
            guard let outStreamIndex = streamMapping[inStreamIndex], outStreamIndex >= 0 else {
                av_packet_unref(packet)
                continue
            }

            let inStream = inputFormatContext!.pointee.streams.advanced(by: inStreamIndex).pointee!
            let outStream = outputFormatContext!.pointee.streams.advanced(by: outStreamIndex).pointee!

            // Fix codec tag for HEVC (hev1 -> hvc1 for iOS compatibility)
            if inStream.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_HEVC {
                outStream.pointee.codecpar.pointee.codec_tag = MKTAG("h".utf8.first!, "v".utf8.first!, "c".utf8.first!, "1".utf8.first!)
            }

            // Rescale timestamps
            packet!.pointee.stream_index = Int32(outStreamIndex)
            av_packet_rescale_ts(
                packet!,
                inStream.pointee.time_base,
                outStream.pointee.time_base
            )

            // Write packet
            guard av_interleaved_write_frame(outputFormatContext, packet) >= 0 else {
                av_packet_unref(packet)
                continue
            }

            av_packet_unref(packet)

            // Flush output buffer periodically
            flushOutputBuffer()
        }

        // Write trailer
        av_write_trailer(outputContext)
        flushOutputBuffer()

        cleanup()

        delegate?.remuxerDidComplete(error: nil)
    }

    private func setupStreams() -> Bool {
        guard let inputContext = inputFormatContext,
              let outputContext = outputFormatContext else { return false }

        streamMapping.removeAll()

        for i in 0..<Int(inputContext.pointee.nb_streams) {
            let inStream = inputContext.pointee.streams.advanced(by: i).pointee!
            let codecParams = inStream.pointee.codecpar

            // Skip unknown codecs
            if codecParams.pointee.codec_id == AV_CODEC_ID_NONE {
                streamMapping[i] = -1
                continue
            }

            // Create output stream
            let outStream = avformat_new_stream(outputContext, nil)
            guard outStream != nil else { return false }

            // Copy codec parameters
            guard avcodec_parameters_copy(outStream!.pointee.codecpar, codecParams) >= 0 else {
                return false
            }

            // Fix codec tag for HEVC
            if codecParams.pointee.codec_id == AV_CODEC_ID_HEVC {
                outStream!.pointee.codecpar.pointee.codec_tag = MKTAG("h".utf8.first!, "v".utf8.first!, "c".utf8.first!, "1".utf8.first!)
            }

            // Copy time base
            outStream!.pointee.time_base = inStream.pointee.time_base

            streamMapping[i] = Int(outStream!.pointee.index)
        }

        return true
    }

    private func flushOutputBuffer() {
        // In a real implementation with custom AVIOContext,
        // this would flush the buffer to the delegate
        // For now, this is a placeholder
    }

    private func cleanup() {
        if let outputContext = outputFormatContext {
            if outputContext.pointee.pb != nil {
                avio_close(outputContext.pointee.pb)
            }
            avformat_free_context(outputContext)
        }

        if let inputContext = inputFormatContext {
            var ctx = inputContext
            avformat_close_input(&ctx)
        }

        outputFormatContext = nil
        inputFormatContext = nil
    }
}

// MARK: - Helpers

private func MKTAG(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
    return UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
}

// AVERROR_EOF constant
private let AVERROR_EOF: Int32 = -541478725
