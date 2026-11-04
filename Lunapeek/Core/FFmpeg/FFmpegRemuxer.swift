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

/// Context for IO callbacks
private class IOContext {
    var readCallback: ((Int64, Int) async throws -> Data)?
    var writeCallback: ((Data) -> Void)?
    var seekCallback: ((Int64, Int) -> Int64)?
    var fileSize: Int64 = 0
    var currentPosition: Int64 = 0
    var outputBuffer = Data()
    let bufferLock = NSLock()

    init() {}
}

/// FFmpeg-based remuxer for converting MKV/WebM/AVI/etc to MP4 on-the-fly.
public final class FFmpegRemuxer: @unchecked Sendable {
    private var inputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var outputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var streamMapping: [Int: Int] = [:]
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.lunapeek.remuxer", qos: .userInitiated)
    private weak var delegate: RemuxerOutputDelegate?
    private var ioContext = IOContext()

    // C callbacks are stored to prevent deallocation
    private var inputIO: UnsafeMutablePointer<AVIOContext>?
    private var outputIO: UnsafeMutablePointer<AVIOContext>?

    public init() {}

    /// Start remuxing from a file URL.
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

    /// Start remuxing from a custom data source.
    public func start(
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data,
        delegate: RemuxerOutputDelegate
    ) {
        self.delegate = delegate
        ioContext.readCallback = readCallback
        ioContext.fileSize = fileSize

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.remuxWithCustomIO(fileSize: fileSize)
            } catch {
                self.delegate?.remuxerDidComplete(error: error)
            }
        }
    }

    public func stop() {
        isRunning = false
    }

    // MARK: - C Callbacks (exposed to C)

    func handleRead(buf: UnsafeMutablePointer<UInt8>, size: Int) -> Int {
        guard let readCallback = ioContext.readCallback else { return -1 }

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Error?

        Task {
            do {
                resultData = try await readCallback(ioContext.currentPosition, size)
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            print("Read error: \(error)")
            return -1
        }

        guard let data = resultData else { return -1 }

        data.withUnsafeBytes { bytes in
            memcpy(buf, bytes.baseAddress, data.count)
        }

        ioContext.currentPosition += Int64(data.count)
        return data.count
    }

    func handleWrite(buf: UnsafePointer<UInt8>, size: Int) -> Int {
        let data = Data(bytes: buf, count: size)

        ioContext.bufferLock.lock()
        ioContext.outputBuffer.append(data)
        let shouldFlush = ioContext.outputBuffer.count >= 65536
        let dataToSend = shouldFlush ? ioContext.outputBuffer : nil
        if shouldFlush {
            ioContext.outputBuffer = Data()
        }
        ioContext.bufferLock.unlock()

        if let dataToSend = dataToSend {
            delegate?.remuxerDidOutputData(dataToSend)
        }

        return size
    }

    func handleSeek(offset: Int64, whence: Int) -> Int64 {
        let SEEK_SET = 0
        let SEEK_CUR = 1
        let SEEK_END = 2
        let AVSEEK_SIZE = 0x10000

        if whence == AVSEEK_SIZE {
            return ioContext.fileSize
        }

        switch whence {
        case SEEK_SET:
            ioContext.currentPosition = offset
        case SEEK_CUR:
            ioContext.currentPosition += offset
        case SEEK_END:
            ioContext.currentPosition = ioContext.fileSize + offset
        default:
            return -1
        }

        return ioContext.currentPosition
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

        // Create output
        try createOutputAndRemux()
    }

    private func remuxWithCustomIO(fileSize: Int64) throws {
        isRunning = true

        // Create input format context
        var formatContext: UnsafeMutablePointer<AVFormatContext>?
        formatContext = avformat_alloc_context()
        guard formatContext != nil else {
            throw RemuxerError.failedToOpenInput
        }

        // Create custom input IO
        let ioCtx = ff_create_input_io(Unmanaged.passUnretained(self).toOpaque(), fileSize)
        guard ioCtx != nil else {
            avformat_free_context(formatContext)
            throw RemuxerError.failedToOpenInput
        }

        inputIO = ioCtx
        formatContext!.pointee.pb = ioCtx

        // Open input (probing format from IO)
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

        // Create output
        try createOutputAndRemux()
    }

    private func createOutputAndRemux() throws {
        guard let inputContext = inputFormatContext else {
            throw RemuxerError.failedToOpenInput
        }

        // Create output format context (MP4)
        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outputContext, nil, "mp4", nil) >= 0 else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

        outputFormatContext = outputContext

        // Create custom output IO
        let ioCtx = ff_create_output_io(Unmanaged.passUnretained(self).toOpaque())
        guard ioCtx != nil else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

        outputIO = ioCtx
        outputContext!.pointee.pb = ioCtx
        outputContext!.pointee.flags |= AVFMT_FLAG_CUSTOM_IO

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
        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }

        while isRunning {
            let ret = av_read_frame(inputContext, packet)
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

            let inStream = inputContext.pointee.streams.advanced(by: inStreamIndex).pointee!
            let outStream = outputContext!.pointee.streams.advanced(by: outStreamIndex).pointee!

            // Fix codec tag for HEVC
            if inStream.pointee.codecpar?.pointee.codec_id == AV_CODEC_ID_HEVC {
                outStream.pointee.codecpar?.pointee.codec_tag = MKTAG("h".utf8.first!, "v".utf8.first!, "c".utf8.first!, "1".utf8.first!)
            }

            // Rescale timestamps
            packet!.pointee.stream_index = Int32(outStreamIndex)
            av_packet_rescale_ts(
                packet!,
                inStream.pointee.time_base,
                outStream.pointee.time_base
            )

            // Write packet
            guard av_interleaved_write_frame(outputContext, packet) >= 0 else {
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

    private func setupStreams() -> Bool {
        guard let inputContext = inputFormatContext,
              let outputContext = outputFormatContext else { return false }

        streamMapping.removeAll()

        for i in 0..<Int(inputContext.pointee.nb_streams) {
            let inStream = inputContext.pointee.streams.advanced(by: i).pointee!
            guard let codecParams = inStream.pointee.codecpar else { continue }

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
                outStream.pointee.codecpar?.pointee.codec_tag = MKTAG("h".utf8.first!, "v".utf8.first!, "c".utf8.first!, "1".utf8.first!)
            }

            // Copy time base
            outStream!.pointee.time_base = inStream.pointee.time_base

            streamMapping[i] = Int(outStream!.pointee.index)
        }

        return true
    }

    private func flushOutputBuffer() {
        ioContext.bufferLock.lock()
        let dataToSend = ioContext.outputBuffer.isEmpty ? nil : ioContext.outputBuffer
        ioContext.outputBuffer = Data()
        ioContext.bufferLock.unlock()

        if let data = dataToSend {
            delegate?.remuxerDidOutputData(data)
        }
    }

    private func cleanup() {
        if let outputContext = outputFormatContext {
            if outputContext.pointee.pb != nil {
                avio_close(outputContext.pointee.pb)
            }
            avformat_free_context(outputContext)
        }

        if let inputContext = inputFormatContext {
            var ctx: UnsafeMutablePointer<AVFormatContext>? = inputContext
            avformat_close_input(&ctx)
        }

        // Free IO contexts
        if let io = inputIO {
            ff_free_io(io)
        }
        if let io = outputIO {
            ff_free_io(io)
        }

        outputFormatContext = nil
        inputFormatContext = nil
        inputIO = nil
        outputIO = nil
    }
}

// MARK: - Helpers

private func MKTAG(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
    return UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
}

private let AVERROR_EOF: Int32 = -541478725
