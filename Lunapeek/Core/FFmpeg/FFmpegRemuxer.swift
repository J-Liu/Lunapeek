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

    // Output buffer for custom AVIOContext
    private var outputBuffer = Data()
    private let bufferLock = NSLock()
    private var avioContext: UnsafeMutablePointer<AVIOContext>?
    private var avioBuffer: UnsafeMutablePointer<UInt8>?

    // Ring buffer configuration
    private let maxBufferSize = 10 * 1024 * 1024 // 10MB max buffer
    private var totalBytesWritten: Int64 = 0
    private var totalBytesRead: Int64 = 0

    public init() {}

    /// Start remuxing from a file URL.
    /// - Parameters:
    ///   - url: Input file URL (local or network)
    ///   - delegate: Delegate to receive remuxed data
    public func start(url: URL, delegate: RemuxerOutputDelegate) {
        self.delegate = delegate

        // Use background QoS for remuxing to not block UI
        let backgroundQueue = DispatchQueue(
            label: "com.lunapeek.remuxer.background",
            qos: .background,
            attributes: .concurrent
        )

        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.remux(url: url)
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.remuxerDidComplete(error: error)
                }
            }
        }
    }

    /// Start remuxing from a custom data source.
    /// - Parameters:
    ///   - fileName: Original filename (for format detection)
    ///   - fileSize: Total file size
    ///   - readCallback: Async callback to read data at offset
    ///   - delegate: Delegate to receive remuxed data
    public func start(
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data,
        delegate: RemuxerOutputDelegate
    ) {
        self.delegate = delegate

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.remuxWithCustomReader(
                    fileName: fileName,
                    fileSize: fileSize,
                    readCallback: readCallback
                )
            } catch {
                self.delegate?.remuxerDidComplete(error: error)
            }
        }
    }

    /// Stop remuxing.
    public func stop() {
        isRunning = false
    }

    /// Seek to a specific timestamp (in seconds).
    /// - Parameter timestamp: Target timestamp in seconds
    /// - Returns: True if seek was successful
    @discardableResult
    public func seek(to timestamp: Double) -> Bool {
        guard let inputContext = inputFormatContext else { return false }

        // Find video stream for time base
        var videoStream: UnsafeMutablePointer<AVStream>?
        for i in 0..<Int(inputContext.pointee.nb_streams) {
            let stream = inputContext.pointee.streams.advanced(by: i).pointee!
            if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStream = stream
                break
            }
        }

        guard let stream = videoStream else { return false }

        let timeBase = stream.pointee.time_base
        let targetPts = Int64(timestamp * Double(timeBase.den) / Double(timeBase.num))

        // Seek with backward flag to find keyframe
        let ret = av_seek_frame(inputContext, Int32(stream.pointee.index), targetPts, AVSEEK_FLAG_BACKWARD)
        return ret >= 0
    }

    /// Get the duration of the input file (in seconds).
    public var duration: Double {
        guard let inputContext = inputFormatContext else { return 0 }
        return Double(inputContext.pointee.duration) / Double(AV_TIME_BASE)
    }

    /// Get stream information for seek calculations.
    public var streamInfo: [FFmpegStreamInfo] {
        guard let inputContext = inputFormatContext else { return [] }

        var info: [StreamInfo] = []
        for i in 0..<Int(inputContext.pointee.nb_streams) {
            let stream = inputContext.pointee.streams.advanced(by: i).pointee!
            let codecParams = stream.pointee.codecpar

            info.append(StreamInfo(
                index: Int(stream.pointee.index),
                codecType: codecParams.pointee.codec_type == AVMEDIA_TYPE_VIDEO ? .video : .audio,
                timeBase: (num: Int(stream.pointee.time_base.num), den: Int(stream.pointee.time_base.den)),
                duration: Double(stream.pointee.duration) * Double(stream.pointee.time_base.num) / Double(stream.pointee.time_base.den)
            ))
        }
        return info
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

        // Setup custom AVIOContext for memory output
        guard setupCustomAVIOContext() else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

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

    // MARK: - Custom Reader Support

    private func remuxWithCustomReader(
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data
    ) throws {
        isRunning = true

        // Create input format context with custom AVIOContext
        var formatContext: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&formatContext, nil, nil, nil) >= 0 else {
            throw RemuxerError.failedToOpenInput
        }

        // Setup custom input AVIOContext
        guard setupCustomInputAVIOContext(
            formatContext: formatContext!,
            fileName: fileName,
            fileSize: fileSize,
            readCallback: readCallback
        ) else {
            avformat_free_context(formatContext)
            throw RemuxerError.failedToOpenInput
        }

        // Open input
        guard avformat_open_input(&formatContext, nil, nil, nil) >= 0 else {
            cleanup()
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

        // Setup custom output AVIOContext
        guard setupCustomAVIOContext() else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

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

            // Fix codec tag for HEVC
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
            flushOutputBuffer()
        }

        // Write trailer
        av_write_trailer(outputContext)
        flushOutputBuffer()

        cleanup()

        delegate?.remuxerDidComplete(error: nil)
    }

    private func setupCustomInputAVIOContext(
        formatContext: UnsafeMutablePointer<AVFormatContext>,
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data
    ) -> Bool {
        // Allocate AVIO buffer
        let bufferSize = 32768
        guard let buffer = av_malloc(bufferSize) else { return false }

        // Store callback in a context object
        let context = CustomInputContext(
            fileName: fileName,
            fileSize: fileSize,
            readCallback: readCallback
        )

        let readPacketCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = { opaque, buf, size in
            guard let opaque = opaque, let buf = buf else { return -1 }
            // This is a simplified version - real implementation needs async bridging
            return -1
        }

        // For now, return false to indicate custom input is not fully implemented
        // Full implementation requires async bridging which is complex
        return false
    }

    private struct CustomInputContext {
        let fileName: String
        let fileSize: Int64
        let readCallback: (Int64, Int) async throws -> Data
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

    private func setupCustomAVIOContext() -> Bool {
        guard let outputContext = outputFormatContext else { return false }

        // Allocate AVIO buffer
        let bufferSize = 32768
        guard let buffer = av_malloc(bufferSize) else { return false }

        avioBuffer = buffer.assumingMemoryBound(to: UInt8.self)

        // Create custom AVIOContext with write callback
        let writeCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int32) -> Int32 = { opaque, buf, size in
            guard let opaque = opaque, let buf = buf else { return -1 }
            let remuxer = Unmanaged<FFmpegRemuxer>.fromOpaque(opaque).takeUnretainedValue()
            return remuxer.handleWrite(data: buf, size: Int(size))
        }

        let seekCallback: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = { opaque, offset, whence in
            guard let opaque = opaque else { return -1 }
            let remuxer = Unmanaged<FFmpegRemuxer>.fromOpaque(opaque).takeUnretainedValue()
            return remuxer.handleSeek(offset: offset, whence: whence)
        }

        guard let avio = avio_alloc_context(
            avioBuffer,
            Int32(bufferSize),
            1, // write_flag
            Unmanaged.passUnretained(self).toOpaque(),
            nil, // read_packet
            writeCallback,
            seekCallback
        ) else {
            return false
        }

        avioContext = avio
        outputContext.pointee.pb = avio
        outputContext.pointee.flags |= AVFMT_FLAG_CUSTOM_IO

        return true
    }

    private func handleWrite(data: UnsafePointer<UInt8>, size: Int) -> Int32 {
        bufferLock.lock()

        // Check if buffer would exceed max size
        while outputBuffer.count + size > maxBufferSize {
            // Wait for consumer to read data
            bufferLock.unlock()
            Thread.sleep(forTimeInterval: 0.01)
            bufferLock.lock()
        }

        outputBuffer.append(data, count: size)
        totalBytesWritten += Int64(size)

        let shouldFlush = outputBuffer.count >= 65536 // Flush every 64KB
        let dataToSend = shouldFlush ? outputBuffer : nil
        if shouldFlush {
            outputBuffer = Data()
        }
        bufferLock.unlock()

        // Send data to delegate outside the lock
        if let dataToSend = dataToSend {
            delegate?.remuxerDidOutputData(dataToSend)
        }

        return Int32(size)
    }

    private func handleSeek(offset: Int64, whence: Int32) -> Int64 {
        // For streaming output, seeking is not supported
        // Return current position
        return 0
    }

    private func flushOutputBuffer() {
        bufferLock.lock()
        let dataToSend = outputBuffer.isEmpty ? nil : outputBuffer
        outputBuffer = Data()
        bufferLock.unlock()

        if let data = dataToSend {
            delegate?.remuxerDidOutputData(data)
        }
    }

    private func cleanup() {
        if let outputContext = outputFormatContext {
            if outputContext.pointee.pb != nil {
                avio_close(outputContext.pointee.pb)
            }
            // Don't free avioBuffer here, avio_close handles it
            avioBuffer = nil
            avioContext = nil
            avformat_free_context(outputContext)
        }

        if let inputContext = inputFormatContext {
            var ctx = inputContext
            avformat_close_input(&ctx)
        }

        outputFormatContext = nil
        inputFormatContext = nil

        // Clear any remaining data
        bufferLock.lock()
        outputBuffer = Data()
        bufferLock.unlock()
    }
}

// MARK: - Stream Info

public struct FFmpegStreamInfo {
    public let index: Int
    public let codecType: FFmpegMediaCodecType
    public let timeBase: (num: Int, den: Int)
    public let duration: Double

    public enum FFmpegMediaCodecType {
        case video
        case audio
    }
}

// MARK: - Helpers

private func MKTAG(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
    return UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
}

// AVERROR_EOF constant
private let AVERROR_EOF: Int32 = -541478725
