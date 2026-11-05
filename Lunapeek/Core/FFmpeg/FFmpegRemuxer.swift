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
    var readCallback: ((Int64, Int) throws -> Data)?  // Synchronous
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

    // Retained self pointer for C callbacks - must be released in cleanup
    private var retainedSelf: UnsafeMutableRawPointer?

    // Duration in seconds
    public private(set) var duration: Double = 0

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
        readCallback: @escaping (Int64, Int) throws -> Data,
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
        // High-frequency callback - no logging
        guard let readCallback = ioContext.readCallback else {
            return -1
        }

        // Calculate actual readable size
        let availableFromPos = max(0, ioContext.fileSize - ioContext.currentPosition)
        let actualSize = min(Int(size), Int(availableFromPos))

        guard actualSize > 0 else {
            return 0  // EOF
        }

        let readPos = ioContext.currentPosition

        do {
            let data = try readCallback(readPos, actualSize)

            data.withUnsafeBytes { bytes in
                _ = memcpy(buf, bytes.baseAddress, data.count)
            }

            ioContext.currentPosition += Int64(data.count)
            return data.count
        } catch {
            return -1
        }
    }

    func handleWrite(buf: UnsafePointer<UInt8>, size: Int) -> Int {
        // High-frequency callback - no logging
        let data = Data(bytes: buf, count: size)

        ioContext.bufferLock.lock()
        ioContext.outputBuffer.append(data)
        // Flush more frequently (every 32KB) for faster stream start
        let shouldFlush = ioContext.outputBuffer.count >= 32768
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
        // High-frequency callback - minimal logging
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

        debugLog("🔄 remuxWithCustomIO: fileSize=\(fileSize)")

        // Create input format context
        var formatContext: UnsafeMutablePointer<AVFormatContext>?
        formatContext = avformat_alloc_context()
        guard formatContext != nil else {
            debugLog("🔄 Failed to alloc format context")
            throw RemuxerError.failedToOpenInput
        }

        // Create custom input IO - use retained pointer to keep self alive during callbacks
        debugLog("🔄 Creating input IO context")
        let selfPointer = Unmanaged.passRetained(self).toOpaque()
        retainedSelf = selfPointer
        let ioCtx = ff_create_input_io(selfPointer, fileSize)
        guard ioCtx != nil else {
            // Release the retained self if IO creation fails
            Unmanaged<FFmpegRemuxer>.fromOpaque(selfPointer).release()
            retainedSelf = nil
            debugLog("🔄 Failed to create input IO")
            avformat_free_context(formatContext)
            throw RemuxerError.failedToOpenInput
        }

        inputIO = ioCtx
        formatContext!.pointee.pb = ioCtx

        // Open input (probing format from IO)
        debugLog("🔄 Calling avformat_open_input")
        let openResult = avformat_open_input(&formatContext, nil, nil, nil)
        guard openResult >= 0 else {
            debugLog("🔄 avformat_open_input failed: \(openResult)")
            cleanup()
            throw RemuxerError.failedToOpenInput
        }
        debugLog("🔄 avformat_open_input succeeded")

        inputFormatContext = formatContext

        // Retrieve stream info
        debugLog("🔄 Finding stream info")
        let streamInfoResult = avformat_find_stream_info(formatContext, nil)
        guard streamInfoResult >= 0 else {
            debugLog("🔄 avformat_find_stream_info failed: \(streamInfoResult)")
            cleanup()
            throw RemuxerError.failedToFindStreamInfo
        }
        debugLog("🔄 Stream info found")

        // Log input duration
        let inputDuration = formatContext!.pointee.duration
        if inputDuration > 0 {
            duration = Double(inputDuration) / Double(AV_TIME_BASE)
            debugLog("🔄 Input duration: \(duration) seconds (\(inputDuration) in AV_TIME_BASE)")
        } else {
            debugLog("🔄 Input duration: unknown (0)")
        }

        // Create output
        try createOutputAndRemux()
    }

    private func createOutputAndRemux() throws {
        guard let inputContext = inputFormatContext else {
            throw RemuxerError.failedToOpenInput
        }

        // Create output format context
        // Use MP4 format which AVPlayer supports natively for progressive download
        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outputContext, nil, "mp4", nil) >= 0 else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

        outputFormatContext = outputContext

        // Create custom output IO - use the same retained pointer
        guard let selfPointer = retainedSelf else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }
        let ioCtx = ff_create_output_io(selfPointer)
        guard ioCtx != nil else {
            cleanup()
            throw RemuxerError.failedToCreateOutput
        }

        outputIO = ioCtx
        outputContext!.pointee.pb = ioCtx
        outputContext!.pointee.flags |= AVFMT_FLAG_CUSTOM_IO

        // Copy duration from input to output
        // This allows AVPlayer to show correct progress before file is fully remuxed
        let inputDuration = inputContext.pointee.duration
        if inputDuration > 0 {
            outputContext!.pointee.duration = inputDuration
            let durationSec = Double(inputDuration) / Double(AV_TIME_BASE)
            debugLog("🔄 Output duration set: \(durationSec) seconds")
        }

        // Setup streams
        guard setupStreams() else {
            debugLog("🔄 setupStreams failed")
            cleanup()
            throw RemuxerError.failedToSetupStreams
        }
        debugLog("🔄 setupStreams completed")

        // Set MP4 options for fragmented streaming
        // This allows streaming without knowing the final size
        var options: OpaquePointer?
        defer { av_dict_free(&options) }

        // Use fragmented MP4 for streaming - allows writing without seeking
        // frag_discont allows discontinuous fragments for B-frames
        // Remove empty_moov to include duration in header for AVPlayer
        av_dict_set(&options, "movflags", "frag_discont+default_base_moof", 0)

        // Fragment every 2 seconds for smooth streaming
        av_dict_set(&options, "frag_duration", "2000000", 0)  // 2 seconds in microseconds
        av_dict_set(&options, "min_frag_duration", "500000", 0)  // 0.5 seconds minimum

        // Write header
        debugLog("🔄 Writing header")
        let headerResult = avformat_write_header(outputContext, &options)
        guard headerResult >= 0 else {
            debugLog("🔄 Header write failed: \(headerResult)")
            cleanup()
            throw RemuxerError.failedToWriteHeader
        }
        debugLog("🔄 Header written")
        flushOutputBuffer()

        // Process packets - let av_interleaved_write_frame handle buffering and ordering
        // The muxer with interleaved write will handle B-frame reordering automatically
        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }

        debugLog("🔄 Starting packet processing loop")
        var packetCount = 0

        while isRunning {
            let ret = av_read_frame(inputContext, packet)
            if ret < 0 {
                if ret == AVERROR_EOF || ret == -541478725 {
                    debugLog("🔄 EOF reached after \(packetCount) packets")
                    break
                }
                debugLog("🔄 av_read_frame error: \(ret)")
                continue
            }

            packetCount += 1
            // Log progress every 500 packets to reduce logging frequency
            if packetCount % 500 == 0 {
                debugLog("🔄 Processed \(packetCount) packets")
            }

            let inStreamIndex = Int(packet!.pointee.stream_index)
            guard let outStreamIndex = streamMapping[inStreamIndex], outStreamIndex >= 0 else {
                av_packet_unref(packet)
                continue
            }

            let inStream = inputContext.pointee.streams.advanced(by: inStreamIndex).pointee!
            let outStream = outputContext!.pointee.streams.advanced(by: outStreamIndex).pointee!

            // Handle missing timestamps
            if packet!.pointee.pts == AV_NOPTS_VALUE {
                packet!.pointee.pts = 0
            }
            if packet!.pointee.dts == AV_NOPTS_VALUE {
                packet!.pointee.dts = packet!.pointee.pts
            }

            // Rescale timestamps to output time base
            packet!.pointee.stream_index = Int32(outStreamIndex)
            av_packet_rescale_ts(
                packet!,
                inStream.pointee.time_base,
                outStream.pointee.time_base
            )

            // Write packet - av_interleaved_write_frame handles buffering and ordering
            var pkt: UnsafeMutablePointer<AVPacket>? = packet
            let writeRet = av_interleaved_write_frame(outputContext, pkt)
            if writeRet < 0 {
                debugLog("🔄 Failed to write packet: \(writeRet)")
            }
            av_packet_unref(packet)

            // Flush output buffer periodically
            if packetCount % 100 == 0 {
                flushOutputBuffer()
            }
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

        debugLog("🔄 setupStreams: \(inputContext.pointee.nb_streams) streams")
        streamMapping.removeAll()

        for i in 0..<Int(inputContext.pointee.nb_streams) {
            let inStream = inputContext.pointee.streams.advanced(by: i).pointee!
            guard let codecParams = inStream.pointee.codecpar else { continue }

            let codecId = codecParams.pointee.codec_id
            let codecType = codecParams.pointee.codec_type
            debugLog("🔄 Stream \(i): type=\(codecType.rawValue), codec_id=\(codecId.rawValue)")

            // Skip unknown codecs
            if codecId == AV_CODEC_ID_NONE {
                streamMapping[i] = -1
                continue
            }

            // Check if codec is supported by AVPlayer
            var isSupported = false

            if codecType == AVMEDIA_TYPE_VIDEO {
                // AVPlayer supports H.264 and H.265 (8-bit)
                // Note: 10-bit HEVC requires software decoder
                isSupported = codecId == AV_CODEC_ID_H264 || codecId == AV_CODEC_ID_HEVC
                debugLog("🔄 Video codec \(codecId.rawValue): \(isSupported ? "supported" : "NOT supported")")
            } else if codecType == AVMEDIA_TYPE_AUDIO {
                // AVPlayer supports AAC, AC-3, MP3
                // DTS, EAC-3, FLAC, Opus, Vorbis require software decoder
                isSupported = codecId == AV_CODEC_ID_AAC ||
                              codecId == AV_CODEC_ID_AC3 ||
                              codecId == AV_CODEC_ID_MP3
                debugLog("🔄 Audio codec \(codecId.rawValue): \(isSupported ? "supported" : "NOT supported")")
            } else {
                // Skip subtitles and other streams
                debugLog("🔄 Skipping non-video/audio stream (type=\(codecType.rawValue))")
                isSupported = false
            }

            if !isSupported {
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

            // Copy duration from input stream to output stream
            // This helps AVPlayer show correct progress
            let inDuration = inStream.pointee.duration
            if inDuration > 0 {
                outStream!.pointee.duration = inDuration
                // Also set the overall format duration from the longest stream
                let formatDuration = outputContext.pointee.duration
                if inDuration > formatDuration {
                    outputContext.pointee.duration = inDuration
                }
            }

            streamMapping[i] = Int(outStream!.pointee.index)
            debugLog("🔄 Mapped stream \(i) -> \(streamMapping[i]!)")
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
        debugLog("🔄 cleanup: starting")

        if let outputContext = outputFormatContext {
            // Don't call avio_close on custom IO - we free it separately
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

        // Release the retained self pointer
        if let selfPointer = retainedSelf {
            Unmanaged<FFmpegRemuxer>.fromOpaque(selfPointer).release()
            retainedSelf = nil
            debugLog("🔄 cleanup: released retained self")
        }

        debugLog("🔄 cleanup: done")
    }
}

// MARK: - Helpers

private let AVERROR_EOF: Int32 = -541478725

// AV_NOPTS_VALUE is 0x8000000000000000LL (Int64.min)
// This is a macro in C, so we define it here
private let AV_NOPTS_VALUE: Int64 = Int64.min
