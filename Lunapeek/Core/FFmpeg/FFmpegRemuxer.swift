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
        debugLog("🔄 handleRead: pos=\(ioContext.currentPosition), size=\(size)")
        guard let readCallback = ioContext.readCallback else {
            debugLog("🔄 handleRead: no readCallback")
            return -1
        }

        // Calculate actual readable size
        let availableFromPos = max(0, ioContext.fileSize - ioContext.currentPosition)
        let actualSize = min(Int(size), Int(availableFromPos))

        guard actualSize > 0 else {
            debugLog("🔄 handleRead: EOF (pos=\(ioContext.currentPosition), fileSize=\(ioContext.fileSize))")
            return 0  // EOF
        }

        let readPos = ioContext.currentPosition

        do {
            let data = try readCallback(readPos, actualSize)

            data.withUnsafeBytes { bytes in
                _ = memcpy(buf, bytes.baseAddress, data.count)
            }

            ioContext.currentPosition += Int64(data.count)
            debugLog("🔄 handleRead: read \(data.count) bytes, newPos=\(ioContext.currentPosition)")
            return data.count
        } catch {
            debugLog("🔄 handleRead error: \(error)")
            return -1
        }
    }

    func handleWrite(buf: UnsafePointer<UInt8>, size: Int) -> Int {
        let data = Data(bytes: buf, count: size)
        debugLog("🔄 handleWrite: \(size) bytes")

        ioContext.bufferLock.lock()
        ioContext.outputBuffer.append(data)
        let shouldFlush = ioContext.outputBuffer.count >= 65536
        let dataToSend = shouldFlush ? ioContext.outputBuffer : nil
        if shouldFlush {
            ioContext.outputBuffer = Data()
        }
        ioContext.bufferLock.unlock()

        if let dataToSend = dataToSend {
            debugLog("🔄 Flushing \(dataToSend.count) bytes")
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
            debugLog("🔄 handleSeek: AVSEEK_SIZE -> \(ioContext.fileSize)")
            return ioContext.fileSize
        }

        let oldPos = ioContext.currentPosition
        switch whence {
        case SEEK_SET:
            ioContext.currentPosition = offset
        case SEEK_CUR:
            ioContext.currentPosition += offset
        case SEEK_END:
            ioContext.currentPosition = ioContext.fileSize + offset
        default:
            debugLog("🔄 handleSeek: unknown whence \(whence)")
            return -1
        }

        debugLog("🔄 handleSeek: whence=\(whence), offset=\(offset), oldPos=\(oldPos) -> newPos=\(ioContext.currentPosition)")
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

        // Create output
        try createOutputAndRemux()
    }

    private func createOutputAndRemux() throws {
        guard let inputContext = inputFormatContext else {
            throw RemuxerError.failedToOpenInput
        }

        // Create output format context
        // Use MPEG-TS format which handles B-frames and streaming naturally
        // MP4 requires monotonically increasing DTS which doesn't work with B-frames
        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outputContext, nil, "mpegts", nil) >= 0 else {
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

        // Setup streams
        guard setupStreams() else {
            debugLog("🔄 setupStreams failed")
            cleanup()
            throw RemuxerError.failedToSetupStreams
        }
        debugLog("🔄 setupStreams completed")

        // Set MPEG-TS options for streaming playback
        // These are needed for proper PAT/PMT/PCR insertion which AVPlayer requires
        var options: OpaquePointer?
        defer { av_dict_free(&options) }

        // Ensure frequent PAT/PMT tables (needed for streaming)
        // Default values are too infrequent for live streaming
        av_dict_set(&options, "pat_period", "0.1", 0)  // PAT every 100ms
        av_dict_set(&options, "pmt_period", "0.1", 0)  // PMT every 100ms

        // Set PCR interval for proper timing (40ms is standard for DVB)
        // PCR is critical for AVPlayer to synchronize playback
        av_dict_set(&options, "pcr_interval", "40000", 0)  // 40ms in microseconds

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

        // Buffer packets to handle B-frames (DTS may not be monotonically increasing)
        // We need to sort by DTS before writing to ensure valid MPEG-TS output
        final class PacketWrapper {
            let packet: UnsafeMutablePointer<AVPacket>
            let dts: Int64
            init(packet: UnsafeMutablePointer<AVPacket>, dts: Int64) {
                self.packet = packet
                self.dts = dts
            }
        }

        var packetBuffer: [PacketWrapper] = []
        let maxBufferSize = 32

        // Track last DTS per stream to ensure monotonicity after sorting
        var lastDts: [Int: Int64] = [:]

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
            if packetCount % 100 == 0 {
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

            // Copy packet to new allocation for buffering
            let bufferedPacket = av_packet_alloc()
            av_packet_ref(bufferedPacket, packet)
            av_packet_unref(packet)

            // Store with rescaled DTS for sorting
            let wrapper = PacketWrapper(packet: bufferedPacket!, dts: bufferedPacket!.pointee.dts)
            packetBuffer.append(wrapper)

            // Flush buffer when full - sort by DTS and write
            if packetBuffer.count >= maxBufferSize {
                // Sort by DTS (ascending)
                packetBuffer.sort { $0.dts < $1.dts }

                // Write sorted packets with DTS monotonicity enforcement
                for wrapper in packetBuffer {
                    let streamIdx = Int(wrapper.packet.pointee.stream_index)

                    // Ensure DTS is monotonically increasing per stream
                    var dts = wrapper.packet.pointee.dts
                    if let last = lastDts[streamIdx], dts <= last {
                        dts = last + 1
                        wrapper.packet.pointee.dts = dts
                        if wrapper.packet.pointee.pts <= dts {
                            wrapper.packet.pointee.pts = dts
                        }
                    }
                    lastDts[streamIdx] = dts

                    var pkt: UnsafeMutablePointer<AVPacket>? = wrapper.packet
                    let writeRet = av_interleaved_write_frame(outputContext, pkt)
                    if writeRet < 0 {
                        debugLog("🔄 Failed to write packet: \(writeRet), dts=\(dts)")
                    }
                    av_packet_free(&pkt)
                }
                packetBuffer.removeAll()
                flushOutputBuffer()
            }
        }

        // Flush remaining packets in buffer
        if !packetBuffer.isEmpty {
            packetBuffer.sort { $0.dts < $1.dts }
            for wrapper in packetBuffer {
                let streamIdx = Int(wrapper.packet.pointee.stream_index)
                var dts = wrapper.packet.pointee.dts
                if let last = lastDts[streamIdx], dts <= last {
                    dts = last + 1
                    wrapper.packet.pointee.dts = dts
                    if wrapper.packet.pointee.pts <= dts {
                        wrapper.packet.pointee.pts = dts
                    }
                }
                lastDts[streamIdx] = dts

                var pkt: UnsafeMutablePointer<AVPacket>? = wrapper.packet
                let writeRet = av_interleaved_write_frame(outputContext, pkt)
                if writeRet < 0 {
                    debugLog("🔄 Failed to write packet: \(writeRet), dts=\(dts)")
                }
                av_packet_free(&pkt)
            }
            packetBuffer.removeAll()
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

        debugLog("🔄 setupStreams: \(inputContext.pointee.nb_streams) streams")
        streamMapping.removeAll()

        for i in 0..<Int(inputContext.pointee.nb_streams) {
            let inStream = inputContext.pointee.streams.advanced(by: i).pointee!
            guard let codecParams = inStream.pointee.codecpar else { continue }

            let codecId = codecParams.pointee.codec_id
            debugLog("🔄 Stream \(i): codec_id=\(codecId)")

            // Skip unknown codecs
            if codecId == AV_CODEC_ID_NONE {
                streamMapping[i] = -1
                continue
            }

            // Skip codecs not supported in MP4 container
            // subrip = 94225, ssa/ass = 94223-94224, webvtt = 86018, etc.
            if codecId == AV_CODEC_ID_SUBRIP || codecId == AV_CODEC_ID_SSA || codecId == AV_CODEC_ID_ASS || codecId == AV_CODEC_ID_WEBVTT {
                debugLog("🔄 Skipping unsupported subtitle codec \(codecId)")
                streamMapping[i] = -1
                continue
            }

            // Skip EAC3 (Enhanced AC-3) - requires packet parsing before header write
            // which is not compatible with streaming remuxing
            if codecId == AV_CODEC_ID_EAC3 {
                debugLog("🔄 Skipping EAC3 audio (not compatible with streaming remuxing)")
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
            if codecId == AV_CODEC_ID_HEVC {
                outStream?.pointee.codecpar?.pointee.codec_tag = MKTAG("h".utf8.first!, "v".utf8.first!, "c".utf8.first!, "1".utf8.first!)
            }

            // MPEG-TS has a fixed 90kHz timebase (1/90000)
            // FFmpeg's MPEG-TS muxer sets this automatically, don't override
            // The muxer will rescale timestamps internally
            // outStream!.pointee.time_base is set by avformat_new_stream

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

private func MKTAG(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
    return UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
}

private let AVERROR_EOF: Int32 = -541478725

// AV_NOPTS_VALUE is 0x8000000000000000LL (Int64.min)
// This is a macro in C, so we define it here
private let AV_NOPTS_VALUE: Int64 = Int64.min
