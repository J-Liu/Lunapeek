// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import CoreVideo
import Foundation
import FFmpegBridge

/// Player state
public enum LPPlayerState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case error(String)

    public static func == (lhs: LPPlayerState, rhs: LPPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.ready, .ready),
             (.playing, .playing), (.paused, .paused), (.ended, .ended):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Player engine that coordinates demuxer, decoders, and renderers
public final class LPPlayerEngine: LPDemuxerDelegate {
    public private(set) var state: LPPlayerState = .idle
    public var onStateChanged: ((LPPlayerState) -> Void)?
    public var onProgress: ((Double, Double) -> Void)? // currentTime, duration in seconds

    // Core components
    private var demuxer: LPDemuxer?
    private var videoDecoder: LPVideoDecoderProtocol?
    private var audioDecoder: LPAudioDecoderProtocol?

    // Frame queues for producer-consumer pattern
    private let videoFrameQueue = LPFrameQueue<LPVideoFrame>(maxSize: 30)
    private let audioFrameQueue = LPFrameQueue<LPAudioFrame>(maxSize: 60)

    // Renderers (callbacks)
    public var videoRenderer: ((LPVideoFrame) -> Void)?
    public var audioRenderer: ((LPAudioFrame) -> Void)?
    public var videoRendererFlush: (() -> Void)?
    public var audioRendererFlush: (() -> Void)?
    public var videoRendererPlay: (() -> Void)?
    public var videoRendererPause: (() -> Void)?
    public var audioRendererPlay: (() -> Void)?
    public var audioRendererPause: (() -> Void)?
    public var videoRendererSetTime: ((CMTime) -> Void)?  // Set video clock base time

    // Stream tracking
    private var videoStreamIndex: Int?
    private var audioStreamIndex: Int?
    private var videoTimebase: AVRational = AVRational(num: 1, den: 1)
    private var audioTimebase: AVRational = AVRational(num: 1, den: 1)

    // Playback control
    private var isPlaying = false
    private let stateLock = NSLock()

    // Audio clock for synchronization (master clock for progress)
    public let audioClock = LPAudioClock()
    private var hasAudio = false

    // Progress update timer
    private var progressTimer: Timer?

    // Frame statistics (duration in AV_TIME_BASE microseconds)
    public private(set) var currentTime: Int64 = 0
    public private(set) var duration: Int64 = 0  // in microseconds

    public init() {}

    // MARK: - Public API

    /// Open a local file
    public func open(url: URL) async throws {
        state = .loading
        onStateChanged?(.loading)

        demuxer = LPDemuxer()
        guard let demuxer = demuxer else {
            state = .error("Failed to create demuxer")
            throw PlayerError.noDemuxer
        }

        let success = demuxer.open(url: url, delegate: self)
        guard success else {
            state = .error("Failed to open file")
            throw PlayerError.openFailed
        }

        setupStreams()
        state = .ready
        onStateChanged?(.ready)
    }

    /// Open a custom IO stream (SMB/SFTP)
    public func open(
        fileName: String,
        fileSize: Int64,
        readCallback: @escaping (Int64, Int) async throws -> Data,
        seekCallback: ((Int64, Int) -> Int64)?
    ) async throws {
        state = .loading
        onStateChanged?(.loading)

        demuxer = LPDemuxer()
        guard let demuxer = demuxer else {
            state = .error("Failed to create demuxer")
            throw PlayerError.noDemuxer
        }

        let success = demuxer.open(
            fileName: fileName,
            fileSize: fileSize,
            readCallback: readCallback,
            seekCallback: seekCallback,
            delegate: self
        )

        guard success else {
            state = .error("Failed to open stream")
            throw PlayerError.openFailed
        }

        setupStreams()
        state = .ready
        onStateChanged?(.ready)
    }

    /// Start playback
    public func play() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard state == .ready || state == .paused else { return }

        let wasPaused = (state == .paused)

        state = .playing
        onStateChanged?(.playing)
        isPlaying = true

        // Start or resume audio clock
        if hasAudio {
            if wasPaused {
                // Resuming from pause
                audioClock.resume()
            } else {
                // Starting fresh
                audioClock.start()
            }
        }

        // Start progress update timer
        startProgressTimer()

        videoRendererPlay?()
        audioRendererPlay?()
        demuxer?.start()
    }

    /// Pause playback
    public func pause() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard state == .playing else { return }
        state = .paused
        onStateChanged?(.paused)
        isPlaying = false

        // Pause audio clock
        audioClock.pause()

        // Stop progress timer
        stopProgressTimer()

        videoRendererPause?()
        audioRendererPause?()
        // Don't stop demuxer - just stop rendering
        // demuxer?.stop() would cause EOF on resume
    }

    /// Seek to timestamp
    public func seek(to timestamp: Int64) async {
        guard state == .ready || state == .playing || state == .paused else {
            debugLog("⚠️ PlayerEngine: seek() called in invalid state: \(state)")
            return
        }

        let timestampSec = Double(timestamp) / Double(AV_TIME_BASE)
        debugLog("🎬 PlayerEngine: Seeking to \(timestampSec) seconds")

        // Stop demuxer first
        demuxer?.stop()

        // Flush frame queues
        videoFrameQueue.flush()
        audioFrameQueue.flush()

        // Flush decoders
        videoDecoder?.flush()
        audioDecoder?.flush()

        // Flush renderers
        videoRendererFlush?()
        audioRendererFlush?()

        // Seek demuxer - use -1 as stream index to use AV_TIME_BASE units
        let success = demuxer?.seek(to: timestamp, streamIndex: -1) ?? false

        // Set audio clock to target time
        let targetTime = CMTime(seconds: timestampSec, preferredTimescale: 1000000000)
        audioClock.setTime(targetTime)

        // Set video clock base time
        videoRendererSetTime?(targetTime)

        if success {
            debugLog("✅ PlayerEngine: Seek succeeded at \(timestampSec)s")

            // Reset frame queues
            videoFrameQueue.reset()
            audioFrameQueue.reset()

            // Update current time
            currentTime = timestamp

            // Restart if playing
            if state == .playing {
                demuxer?.start()
                videoRendererPlay?()
                audioRendererPlay?()
            }
        } else {
            debugLog("⚠️ PlayerEngine: Seek failed")
        }
    }

    /// Stop and reset
    public func stop() {
        isPlaying = false
        stopProgressTimer()
        demuxer?.stop()

        Thread.sleep(forTimeInterval: 0.1)

        videoDecoder?.close()
        audioDecoder?.close()

        demuxer?.close()

        demuxer = nil
        videoDecoder = nil
        audioDecoder = nil

        videoStreamIndex = nil
        audioStreamIndex = nil
        currentTime = 0
        duration = 0

        audioClock.reset()
        videoFrameQueue.flush()
        audioFrameQueue.flush()

        state = .idle
        onStateChanged?(.idle)
    }

    // MARK: - Private

    private func setupStreams() {
        guard let demuxer = demuxer else { return }

        // Get format duration in microseconds (AV_TIME_BASE)
        duration = demuxer.getDuration()
        let durationSeconds = Double(duration) / Double(AV_TIME_BASE)
        let durationMinutes = durationSeconds / 60
        debugLog("📋 Format duration: \(duration) microseconds (\(durationSeconds) seconds, \(durationMinutes) minutes)")

        let streams = demuxer.getStreams()
        debugLog("📋 Found \(streams.count) streams")

        for stream in streams {
            debugLog("📋 Stream \(stream.index): type=\(stream.type), codec=\(stream.codecId.rawValue)")

            if stream.isVideo && videoStreamIndex == nil {
                videoStreamIndex = stream.index
                videoTimebase = stream.timebase
                let streamDurationSec = Double(stream.duration) * Double(stream.timebase.num) / Double(stream.timebase.den)
                debugLog("📺 Video stream: index=\(stream.index), stream_duration=\(stream.duration) (\(streamDurationSec) seconds), timebase=\(stream.timebase.num)/\(stream.timebase.den)")

                // Check if codec needs software decoding (10-bit HEVC, VP9, etc.)
                let needsSoftwareDecoding = Self.needsSoftwareDecoding(
                    codecId: stream.codecId,
                    codecParams: stream.codecParams
                )

                if needsSoftwareDecoding {
                    // Use FFmpeg software decoder
                    videoDecoder = FFmpegSoftwareDecoder()
                    let success = videoDecoder?.open(codecParams: stream.codecParams, streamIndex: stream.index) ?? false
                    if success {
                        debugLog("📺 Video stream: \(stream.index), codec: \(stream.codecId) (SOFTWARE)")
                    } else {
                        debugLog("❌ Video stream: \(stream.index), codec: \(stream.codecId) (SOFTWARE FAILED)")
                        videoDecoder = nil
                        continue
                    }
                } else {
                    // Try VideoToolbox hardware decoder first
                    let vtDecoder = VideoToolboxDecoder()
                    let success = vtDecoder.open(codecParams: stream.codecParams, streamIndex: stream.index)

                    if success {
                        videoDecoder = vtDecoder
                        debugLog("📺 Video stream: \(stream.index), codec: \(stream.codecId) (HARDWARE)")
                    } else {
                        // Fallback to software decoder
                        debugLog("📺 Video stream: \(stream.index), codec: \(stream.codecId) (HARDWARE FAILED, falling back to SOFTWARE)")
                        videoDecoder = FFmpegSoftwareDecoder()
                        videoDecoder?.timebase = videoTimebase
                        videoDecoder?.onFrameDecoded = { [weak self] frame in
                            self?.handleVideoFrame(frame)
                        }
                        let softSuccess = videoDecoder?.open(codecParams: stream.codecParams, streamIndex: stream.index) ?? false
                        if !softSuccess {
                            debugLog("❌ FFmpegSoft: Failed to open as fallback")
                        }
                        continue
                    }
                }

                videoDecoder?.timebase = videoTimebase
                videoDecoder?.onFrameDecoded = { [weak self] frame in
                    self?.handleVideoFrame(frame)
                }

            } else if stream.isAudio && audioStreamIndex == nil {
                audioStreamIndex = stream.index
                audioTimebase = stream.timebase
                hasAudio = true

                // Check if codec needs software decoding
                let needsSoftwareAudio = Self.needsSoftwareAudioDecoding(codecId: stream.codecId)

                if needsSoftwareAudio {
                    // Use FFmpeg software audio decoder
                    audioDecoder = FFmpegAudioDecoder()
                    let success = audioDecoder?.open(codecParams: stream.codecParams, streamIndex: stream.index) ?? false
                    if success {
                        debugLog("🔊 Audio stream: \(stream.index), codec: \(stream.codecId) (SOFTWARE)")
                    } else {
                        debugLog("❌ Audio stream: \(stream.index), codec: \(stream.codecId) (SOFTWARE FAILED)")
                        audioDecoder = nil
                        continue
                    }
                } else {
                    // Try AudioToolbox hardware decoder first
                    let atDecoder = AudioToolboxDecoder()
                    let success = atDecoder.open(codecParams: stream.codecParams, streamIndex: stream.index)

                    if success {
                        audioDecoder = atDecoder
                        debugLog("🔊 Audio stream: \(stream.index), codec: \(stream.codecId) (HARDWARE)")
                    } else {
                        // Fallback to software decoder
                        debugLog("🔊 Audio stream: \(stream.index), codec: \(stream.codecId) (HARDWARE FAILED, falling back to SOFTWARE)")
                        audioDecoder = FFmpegAudioDecoder()
                        audioDecoder?.timebase = audioTimebase
                        audioDecoder?.onAudioDecoded = { [weak self] frame in
                            self?.handleAudioFrame(frame)
                        }
                        let softSuccess = audioDecoder?.open(codecParams: stream.codecParams, streamIndex: stream.index) ?? false
                        if !softSuccess {
                            debugLog("❌ FFmpegAudio: Failed to open as fallback")
                        }
                        continue
                    }
                }

                audioDecoder?.timebase = audioTimebase
                audioDecoder?.onAudioDecoded = { [weak self] frame in
                    self?.handleAudioFrame(frame)
                }
            }
        }
    }

    /// Check if video codec requires software decoding
    private static func needsSoftwareDecoding(codecId: AVCodecID, codecParams: UnsafeMutablePointer<AVCodecParameters>) -> Bool {
        switch codecId {
        case AV_CODEC_ID_HEVC:
            // Check for 10-bit HEVC
            let profile = codecParams.pointee.profile
            let bitDepth = codecParams.pointee.bits_per_coded_sample
            if profile == 2 || bitDepth > 8 {
                return true // 10-bit HEVC needs software decoding
            }
            return false // 8-bit HEVC can use VideoToolbox

        case AV_CODEC_ID_VP9, AV_CODEC_ID_AV1, AV_CODEC_ID_VC1:
            // VP9, AV1, VC-1 always need software decoding
            return true

        default:
            // Other codecs (H.264, MPEG-2, etc.) can use VideoToolbox
            return false
        }
    }

    /// Check if audio codec requires software decoding
    private static func needsSoftwareAudioDecoding(codecId: AVCodecID) -> Bool {
        switch codecId {
        case AV_CODEC_ID_EAC3, AV_CODEC_ID_DTS, AV_CODEC_ID_TRUEHD, AV_CODEC_ID_FLAC, AV_CODEC_ID_OPUS, AV_CODEC_ID_VORBIS:
            // These codecs need software decoding
            return true

        default:
            // AAC, AC-3, MP3, PCM can use AudioToolbox
            return false
        }
    }

    // MARK: - LPDemuxerDelegate

    public func demuxerDidReadPacket(_ packet: UnsafeMutablePointer<AVPacket>, streamIndex: Int) {
        let streamIdx = Int(packet.pointee.stream_index)

        if streamIdx == videoStreamIndex {
            videoDecoder?.decode(packet: packet)
        } else if streamIdx == audioStreamIndex {
            audioDecoder?.decode(packet: packet)
        }
    }

    public func demuxerDidComplete(error: Error?) {
        debugLog("🎬 PlayerEngine: demuxerDidComplete, error: \(error?.localizedDescription ?? "nil")")
        if let error = error {
            state = .error(error.localizedDescription)
            onStateChanged?(.error(error.localizedDescription))
        } else {
            debugLog("🎬 PlayerEngine: Setting state to .ended")
            state = .ended
            onStateChanged?(.ended)
        }
        isPlaying = false
    }

    public func demuxerDidUpdateProgress(_ progress: Double) {
        currentTime = Int64(progress * Double(duration))
    }

    // MARK: - Frame Handlers

    private func handleVideoFrame(_ frame: LPVideoFrame) {
        guard isPlaying else { return }

        // Push to video frame queue
        videoFrameQueue.push(frame)

        // Also send to renderer callback for compatibility
        videoRenderer?(frame)

        // Update current time from frame PTS (for non-audio case)
        // This is used as fallback when there's no audio clock
        let ptsMicroseconds = Int64(frame.pts.seconds * Double(AV_TIME_BASE))
        currentTime = ptsMicroseconds
        // Don't call notifyProgress here - the timer handles it
    }

    private func handleAudioFrame(_ frame: LPAudioFrame) {
        guard isPlaying else { return }

        // Push to audio frame queue
        audioFrameQueue.push(frame)

        // Also send to renderer callback
        audioRenderer?(frame)
    }

    private func notifyProgress() {
        guard duration > 0 else {
            debugLog("⏱️ notifyProgress: duration is \(duration), skipping")
            return
        }

        // Use audio clock as master for current time (like KSPlayer)
        // If no audio, fall back to tracking via video frames
        let currentSeconds: Double
        if hasAudio {
            currentSeconds = audioClock.currentTimeSeconds
        } else {
            // currentTime is already in AV_TIME_BASE (microseconds)
            // Convert to seconds
            currentSeconds = Double(currentTime) / Double(AV_TIME_BASE)
        }

        let durationSeconds = Double(duration) / Double(AV_TIME_BASE)

        onProgress?(currentSeconds, durationSeconds)
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        // Stop any existing timer
        stopProgressTimer()

        // Create timer on main thread
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.notifyProgress()
            }
        }
    }

    private func stopProgressTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
    }
}

// MARK: - Errors

public enum PlayerError: Error {
    case noDemuxer
    case noDecoder
    case openFailed
    case notReady
}
