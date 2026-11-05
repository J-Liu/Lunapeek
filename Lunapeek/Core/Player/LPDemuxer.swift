// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import FFmpegBridge

/// Stream type enumeration
public enum LPStreamType {
    case video
    case audio
    case subtitle
    case unknown
}

/// Stream info extracted from demuxer
public struct LPStreamInfo {
    public let index: Int
    public let type: LPStreamType
    public let codecId: AVCodecID
    public let codecParams: UnsafeMutablePointer<AVCodecParameters>
    public let timebase: AVRational
    public let duration: Int64

    public var isVideo: Bool { type == .video }
    public var isAudio: Bool { type == .audio }
}

/// Demuxer delegate protocol
public protocol LPDemuxerDelegate: AnyObject {
    func demuxerDidReadPacket(_ packet: UnsafeMutablePointer<AVPacket>, streamIndex: Int)
    func demuxerDidComplete(error: Error?)
    func demuxerDidUpdateProgress(_ progress: Double)
}

/// FFmpeg-based demuxer that reads packets from media files/streams
public final class LPDemuxer {
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var ioContext: UnsafeMutablePointer<AVIOContext>?
    private var customIO: CustomIOContext?
    private var streams: [LPStreamInfo] = []
    private var isRunning = false
    private var isReading = false  // Track if read loop is active
    private var isStopping = false  // Track if we're in stop() to prevent callbacks
    private let queue = DispatchQueue(label: "com.lunapeek.demuxer", qos: .userInitiated)
    private weak var delegate: LPDemuxerDelegate?

    // Seek validation
    private var expectedSeekPts: Int64?  // Expected position after seek (in AV_TIME_BASE)
    private var isSeeking = false  // Track if we're in seek mode

    public init() {}

    // MARK: - Public API

    /// Open a local file
    public func open(url: URL, delegate: LPDemuxerDelegate) -> Bool {
        self.delegate = delegate

        // Create format context
        var ctx: UnsafeMutablePointer<AVFormatContext>?
        // Use absoluteString for HTTP URLs, path for local files
        let urlString = url.scheme == "http" || url.scheme == "https" ? url.absoluteString : url.path
        let result = avformat_open_input(&ctx, urlString, nil, nil)

        guard result == 0, let formatCtx = ctx else {
            debugLog("❌ Demuxer: Failed to open input: \(urlString), error: \(result)")
            return false
        }

        formatContext = formatCtx

        // Find stream info
        let infoResult = avformat_find_stream_info(formatCtx, nil)
        guard infoResult >= 0 else {
            debugLog("❌ Demuxer: Failed to find stream info, error: \(infoResult)")
            close()
            return false
        }

        // Extract stream info
        extractStreamInfo()

        debugLog("✅ Demuxer: Opened \(url.lastPathComponent), \(streams.count) streams")
        return true
    }

    /// Open a custom IO stream (for SMB/SFTP)
    public func open(
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data,
        seekCallback: ((Int64, Int) -> Int64)?,
        delegate: LPDemuxerDelegate
    ) -> Bool {
        self.delegate = delegate

        // Create custom IO context
        customIO = CustomIOContext(
            fileName: fileName,
            fileSize: fileSize,
            readCallback: readCallback,
            seekCallback: seekCallback
        )

        // Create format context
        var ctx: UnsafeMutablePointer<AVFormatContext>?
        let result = avformat_open_input(&ctx, fileName, nil, nil)

        guard result == 0, let formatCtx = ctx else {
            debugLog("❌ Demuxer: Failed to open custom IO, error: \(result)")
            return false
        }

        formatContext = formatCtx

        // Setup custom AVIO context
        guard setupCustomIO(formatCtx: formatCtx) else {
            close()
            return false
        }

        // Find stream info
        let infoResult = avformat_find_stream_info(formatCtx, nil)
        guard infoResult >= 0 else {
            debugLog("❌ Demuxer: Failed to find stream info, error: \(infoResult)")
            close()
            return false
        }

        // Extract stream info
        extractStreamInfo()

        debugLog("✅ Demuxer: Opened custom IO, \(streams.count) streams")
        return true
    }

    /// Get stream info for all streams
    public func getStreams() -> [LPStreamInfo] {
        return streams
    }

    /// Get stream info for a specific type
    public func getStreams(ofType type: LPStreamType) -> [LPStreamInfo] {
        return streams.filter { $0.type == type }
    }

    /// Get duration in AV_TIME_BASE units (microseconds)
    public func getDuration() -> Int64 {
        guard let formatCtx = formatContext else { return 0 }

        // Try container duration first
        let containerDuration = formatCtx.pointee.duration

        // If container duration is valid, use it
        if containerDuration > 0 {
            return containerDuration
        }

        // Fallback: check individual streams for duration
        for stream in streams {
            let streamDuration = stream.duration
            if streamDuration > 0 {
                // Convert from stream timebase to AV_TIME_BASE
                let avTimebaseQ = AVRational(num: 1, den: Int32(AV_TIME_BASE))
                return av_rescale_q(streamDuration, stream.timebase, avTimebaseQ)
            }
        }

        return 0
    }

    /// Start reading packets
    public func start() {
        guard let formatCtx = formatContext else { return }

        // Only start if not already running
        guard !isRunning else {
            debugLog("📋 Demuxer: start() called but already running, skipping")
            return
        }

        debugLog("📋 Demuxer: start() called, setting isRunning=true")
        isRunning = true

        queue.async { [weak self] in
            guard let self = self else { return }
            self.readPackets(formatCtx)
        }
    }

    /// Stop reading
    public func stop() {
        debugLog("📋 Demuxer: stop() called, setting isRunning=false")
        isStopping = true  // Prevent callbacks during stop
        isRunning = false
        // Don't wait for read loop - let it exit on its own
        // This prevents deadlocks when stop() is called from main thread
        // while read loop is waiting in av_read_frame
    }

    /// Seek to timestamp
    public func seek(to timestamp: Int64, streamIndex: Int? = nil) -> Bool {
        guard let formatCtx = formatContext else { return false }

        // Store expected seek position for validation in readPackets
        expectedSeekPts = timestamp
        isSeeking = true

        // Determine which stream to use for seeking
        var streamIdx = streamIndex
        if streamIdx == nil {
            // Find first video stream
            for stream in streams {
                if stream.isVideo {
                    streamIdx = stream.index
                    break
                }
            }
        }

        let finalStreamIdx = streamIdx ?? -1

        // Log timestamp - if streamIdx is specified, timestamp is in stream timebase
        // otherwise it's in AV_TIME_BASE
        if let idx = streamIdx, let stream = streams.first(where: { $0.index == idx }) {
            // Timestamp is in stream timebase - convert to seconds
            let timestampSec = Double(timestamp) * Double(stream.timebase.num) / Double(stream.timebase.den)
            debugLog("📋 Demuxer: Seeking to \(timestampSec) seconds (ts=\(timestamp), stream=\(finalStreamIdx), timebase=\(stream.timebase.num)/\(stream.timebase.den))")
        } else {
            // Timestamp is in AV_TIME_BASE
            let timestampSec = Double(timestamp) / Double(AV_TIME_BASE)
            debugLog("📋 Demuxer: Seeking to \(timestampSec) seconds (ts=\(timestamp), stream=\(finalStreamIdx), timebase=AV_TIME_BASE)")
        }

        // Wait for read loop to stop (max 200ms)
        // This is necessary because FFmpeg seek operations require no concurrent reads
        var waitCount = 0
        while isReading && waitCount < 20 {
            Thread.sleep(forTimeInterval: 0.01)
            waitCount += 1
        }
        if isReading {
            debugLog("⚠️ Demuxer: seek() - read loop still active, proceeding anyway")
        }

        // Use avformat_seek_file instead of av_seek_frame for more robust seeking
        // This allows specifying a range, which helps with corrupt MKV Cues
        // Tolerance: 5 seconds in the appropriate timebase
        let tolerance: Int64
        if streamIdx != nil, let stream = streams.first(where: { $0.index == streamIdx! }) {
            // Convert 5 seconds to stream timebase
            tolerance = 5 * Int64(stream.timebase.den) / Int64(stream.timebase.num)
        } else {
            // 5 seconds in AV_TIME_BASE (microseconds)
            tolerance = 5 * Int64(AV_TIME_BASE)
        }

        let minTs = max(0, timestamp - tolerance)
        let maxTs = timestamp + tolerance

        // AVSEEK_FLAG_BACKWARD: seek to nearest keyframe before target
        let flags: Int32 = AVSEEK_FLAG_BACKWARD

        let result = avformat_seek_file(formatCtx, Int32(finalStreamIdx), minTs, timestamp, maxTs, flags)
        if result < 0 {
            debugLog("⚠️ Demuxer: avformat_seek_file failed, error: \(result), trying av_seek_frame fallback")

            // Fallback to simple av_seek_frame
            let fallbackResult = av_seek_frame(formatCtx, Int32(finalStreamIdx), timestamp, flags)
            if fallbackResult < 0 {
                debugLog("⚠️ Demuxer: av_seek_frame also failed, error: \(fallbackResult)")
                expectedSeekPts = nil
                return false
            }
        }

        debugLog("✅ Demuxer: Seek succeeded")
        return true
    }

    /// Close and cleanup
    public func close() {
        isRunning = false
        if let ctx = formatContext {
            var closeCtx: UnsafeMutablePointer<AVFormatContext>? = ctx
            avformat_close_input(&closeCtx)
            formatContext = nil
        }
        ioContext = nil
        customIO = nil
        streams.removeAll()
    }

    // MARK: - Private

    private func extractStreamInfo() {
        guard let formatCtx = formatContext else { return }

        streams.removeAll()
        let nbStreams = Int(formatCtx.pointee.nb_streams)

        for i in 0..<nbStreams {
            guard let stream = formatCtx.pointee.streams?[i] else { continue }
            let codecParams = stream.pointee.codecpar

            let type: LPStreamType
            switch codecParams!.pointee.codec_type {
            case AVMEDIA_TYPE_VIDEO:
                type = .video
            case AVMEDIA_TYPE_AUDIO:
                type = .audio
            case AVMEDIA_TYPE_SUBTITLE:
                type = .subtitle
            default:
                type = .unknown
            }

            let info = LPStreamInfo(
                index: i,
                type: type,
                codecId: codecParams!.pointee.codec_id,
                codecParams: codecParams!,
                timebase: stream.pointee.time_base,
                duration: stream.pointee.duration
            )

            streams.append(info)
        }
    }

    private func setupCustomIO(formatCtx: UnsafeMutablePointer<AVFormatContext>) -> Bool {
        guard let customIO = customIO else { return false }

        // Create buffer for IO
        let bufferSize: Int32 = 4096
        let buffer = av_malloc(Int(bufferSize))

        guard let buffer = buffer else {
            debugLog("❌ Demuxer: Failed to allocate IO buffer")
            return false
        }

        // Create AVIO context with callbacks
        let ioCtx = avio_alloc_context(
            buffer.assumingMemoryBound(to: UInt8.self),
            bufferSize,
            0,  // Read-only
            Unmanaged.passUnretained(customIO).toOpaque(),
            LPDemuxer.readPacketCallback,
            nil,  // Write callback (not used)
            LPDemuxer.seekCallback
        )

        guard let ioCtx = ioCtx else {
            debugLog("❌ Demuxer: Failed to create AVIO context")
            return false
        }

        ioContext = ioCtx
        formatCtx.pointee.pb = ioCtx

        return true
    }

    private func readPackets(_ formatCtx: UnsafeMutablePointer<AVFormatContext>) {
        isReading = true
        defer { isReading = false }

        var packet = AVPacket()
        var packetCount = 0
        var lastPts: Int64 = -1  // Track last PTS to detect unexpected jumps
        var seekValidationDone = false  // Only validate first packet after seek
        let seekToleranceSec: Double = 10.0  // Allow 10 second tolerance for seek validation

        debugLog("📋 Demuxer: Starting read loop, isRunning=\(isRunning)")

        while isRunning {
            let result = av_read_frame(formatCtx, &packet)

            if result < 0 {
                if result == LP_AVERROR_EOF && !isStopping {
                    // Log final position when reaching EOF
                    if lastPts >= 0 {
                        let duration = formatCtx.pointee.duration
                        let lastPtsSec = Double(lastPts) / Double(AV_TIME_BASE)
                        let durationSec = Double(duration) / Double(AV_TIME_BASE)
                        debugLog("📋 Demuxer: Reached EOF at \(lastPtsSec) seconds (expected \(durationSec) seconds) after \(packetCount) packets")
                    }
                    delegate?.demuxerDidComplete(error: nil)
                } else if result != LP_AVERROR_EOF {
                    debugLog("📋 Demuxer: Read error \(result) after \(packetCount) packets")
                    if !isStopping {
                        let error = NSError(domain: "DemuxerError", code: Int(result), userInfo: nil)
                        delegate?.demuxerDidComplete(error: error)
                    }
                }
                break
            }

            packetCount += 1

            // Get packet PTS in AV_TIME_BASE for consistency
            let streamIdx = Int(packet.stream_index)
            let ptsInAvTimebase: Int64
            if let stream = streams.first(where: { $0.index == streamIdx }) {
                ptsInAvTimebase = av_rescale_q(packet.pts, stream.timebase, AVRational(num: 1, den: Int32(AV_TIME_BASE)))
            } else {
                ptsInAvTimebase = packet.pts
            }

            // Validate seek position on first packet
            if !seekValidationDone, let expectedPts = expectedSeekPts, isSeeking {
                let expectedSec = Double(expectedPts) / Double(AV_TIME_BASE)
                let actualSec = Double(ptsInAvTimebase) / Double(AV_TIME_BASE)
                let diff = abs(actualSec - expectedSec)

                if diff > seekToleranceSec {
                    debugLog("⚠️ Demuxer: Seek validation failed - expected \(expectedSec)s, got \(actualSec)s (diff \(diff)s)")
                } else {
                    debugLog("✅ Demuxer: Seek validation passed - expected \(expectedSec)s, got \(actualSec)s")
                }
                seekValidationDone = true
                isSeeking = false  // Clear seeking flag after validation
                expectedSeekPts = nil
            }

            // Detect unexpected PTS jumps (possible corrupt Cues)
            if lastPts >= 0 {
                let jump = abs(ptsInAvTimebase - lastPts)
                let jumpSec = Double(jump) / Double(AV_TIME_BASE)
                if jumpSec > 60.0 {  // More than 60 seconds jump
                    debugLog("⚠️ Demuxer: Unexpected PTS jump from \(Double(lastPts) / Double(AV_TIME_BASE))s to \(Double(ptsInAvTimebase) / Double(AV_TIME_BASE))s (\(jumpSec)s gap)")
                }
            }
            lastPts = ptsInAvTimebase

            // Notify delegate with packet - skip if stopping
            if !isStopping {
                let streamIndex = Int(packet.stream_index)
                delegate?.demuxerDidReadPacket(&packet, streamIndex: streamIndex)
            }

            // Update progress using AV_TIME_BASE consistent values
            let duration = formatCtx.pointee.duration
            if duration > 0 {
                let progress = Double(ptsInAvTimebase) / Double(duration)
                delegate?.demuxerDidUpdateProgress(progress)
            }

            av_packet_unref(&packet)
        }

        debugLog("📋 Demuxer: Read loop ended, total packets=\(packetCount)")
    }

    // MARK: - C Callbacks

    private static let readPacketCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = { opaque, buffer, size in
        guard let opaque = opaque, let buffer = buffer else { return -1 }
        let ctx = Unmanaged<CustomIOContext>.fromOpaque(opaque).takeUnretainedValue()
        return ctx.readPacket(buffer: buffer, size: size)
    }

    private static let seekCallback: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = { opaque, offset, whence in
        guard let opaque = opaque else { return -1 }
        let ctx = Unmanaged<CustomIOContext>.fromOpaque(opaque).takeUnretainedValue()
        return ctx.seek(offset: offset, whence: whence)
    }
}

// MARK: - Custom IO Context

private class CustomIOContext {
    let fileName: String
    let fileSize: Int64
    let readCallback: (Int64, Int) async throws -> Data
    let seekCallback: ((Int64, Int) -> Int64)?
    var position: Int64 = 0

    init(
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data,
        seekCallback: ((Int64, Int) -> Int64)?
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.readCallback = readCallback
        self.seekCallback = seekCallback
    }

    func readPacket(buffer: UnsafeMutablePointer<UInt8>, size: Int32) -> Int32 {
        // This needs to be synchronous for the C callback
        // Use a semaphore to wait for async result
        var result: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        Task { [weak self] in
            guard let self = self else {
                semaphore.signal()
                return
            }

            do {
                let data = try await self.readCallback(self.position, Int(size))
                let readSize = min(data.count, Int(size))
                data.withUnsafeBytes { bytes in
                    memcpy(buffer, bytes.baseAddress!, readSize)
                }
                self.position += Int64(readSize)
                result = Int32(readSize)
            } catch {
                debugLog("⚠️ CustomIO: Read error: \(error)")
                result = -1
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    func seek(offset: Int64, whence: Int32) -> Int64 {
        guard let seekCallback = seekCallback else { return -1 }

        let newPos = seekCallback(offset, Int(whence))
        if newPos >= 0 {
            position = newPos
        }
        return newPos
    }
}

// MARK: - Constants

private let LP_AVERROR_EOF: Int32 = -541478725
