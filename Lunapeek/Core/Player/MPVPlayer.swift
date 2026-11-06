// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import Mpv
import UIKit
import Metal
import QuartzCore

/// Player state
public enum MPVPlayerState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case error(String)
}

/// Swift wrapper for libmpv
public final class MPVPlayer {
    public private(set) var state: MPVPlayerState = .idle
    public var onStateChanged: ((MPVPlayerState) -> Void)?
    public var onProgress: ((Double, Double) -> Void)?
    public var logHandler: ((String) -> Void)?

    private var handle: OpaquePointer?
    private var playerView: MPVPlayerView?

    private var url: URL?
    private var duration: Double = 0
    private var currentTime: Double = 0

    private let eventQueue = DispatchQueue(label: "com.lunapeek.mpv.events", qos: .userInitiated)
    private var isSeeking = false

    public init() {}

    private func log(_ message: String) {
        let fullMessage = "🔵 MPVPlayer: \(message)"
        logHandler?(fullMessage)
        debugLog(fullMessage)
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// The view for video rendering
    public var view: UIView {
        if playerView == nil {
            playerView = MPVPlayerView()
        }
        return playerView!
    }

    /// Open a file URL
    public func open(url: URL) {
        log("open() called with URL: \(url.absoluteString)")
        log("isFileURL: \(url.isFileURL)")
        log("path: \(url.path)")

        self.url = url
        state = .loading
        onStateChanged?(.loading)

        // Create mpv handle
        handle = mpv_create()
        guard let handle = handle else {
            log("ERROR: Failed to create mpv handle")
            state = .error("Failed to create mpv handle")
            onStateChanged?(.error("Failed to create mpv handle"))
            return
        }
        log("mpv handle created")

        // Set options for iOS
        log("Setting options...")
        setOption("hwdec", value: "auto-safe")
        setOption("vo", value: "gpu")
        setOption("gpu-context", value: "ios")
        setOption("vid", value: "auto")
        setOption("aid", value: "auto")
        setOption("keep-open", value: "yes")

        // Initialize
        log("Initializing mpv...")
        let initResult = mpv_initialize(handle)
        guard initResult >= 0 else {
            let error = String(cString: mpv_error_string(initResult))
            log("ERROR: mpv_initialize failed with code \(initResult): \(error)")
            state = .error("mpv_initialize failed: \(error)")
            onStateChanged?(.error("mpv_initialize failed: \(error)"))
            mpv_destroy(handle)
            self.handle = nil
            return
        }
        log("mpv initialized successfully")

        // Observe properties
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)

        // Set up event callback
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx = ctx else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(ctx).takeUnretainedValue()
            player.handleEvents()
        }, unsafeSelf)
        log("Event callback set up")

        // Load file using loadfile command
        let path = url.isFileURL ? url.path : url.absoluteString
        log("Loading file with path: \(path)")

        var args: [UnsafePointer<CChar>?] = [
            UnsafePointer(strdup("loadfile")),
            UnsafePointer(strdup(path)),
            nil
        ]
        let result = mpv_command(handle, &args)

        // Free allocated strings
        for i in 0..<2 {
            if let ptr = args[i] {
                free(UnsafeMutableRawPointer(mutating: ptr))
            }
        }

        if result < 0 {
            let error = String(cString: mpv_error_string(result))
            log("ERROR: mpv_command failed with code \(result): \(error)")
            state = .error("Failed to load file: \(error)")
            onStateChanged?(.error("Failed to load file: \(error)"))
            stop()
        } else {
            log("mpv_command succeeded, waiting for file-loaded event")
        }
    }

    /// Play
    public func play() {
        guard let handle = handle, state == .ready || state == .paused else { return }

        var pause: Int64 = 0
        mpv_set_property(handle, "pause", MPV_FORMAT_INT64, &pause)

        state = .playing
        onStateChanged?(.playing)
    }

    /// Pause
    public func pause() {
        guard let handle = handle, state == .playing else { return }

        var pause: Int64 = 1
        mpv_set_property(handle, "pause", MPV_FORMAT_INT64, &pause)

        state = .paused
        onStateChanged?(.paused)
    }

    /// Seek to timestamp (seconds) - async, non-blocking
    public func seek(to time: Double) {
        guard let handle = handle else { return }

        isSeeking = true
        let timeStr = String(format: "%.2f", time)

        var args: [UnsafePointer<CChar>?] = [
            UnsafePointer(strdup("seek")),
            UnsafePointer(strdup(timeStr)),
            UnsafePointer(strdup("absolute")),
            nil
        ]

        mpv_command_async(handle, 0, &args)

        for i in 0..<3 {
            free(UnsafeMutablePointer(mutating: args[i]))
        }
    }

    /// Stop and reset
    public func stop() {
        if let handle = handle {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
            self.handle = nil
        }

        state = .idle
        onStateChanged?(.idle)
    }

    /// Get current playback time in seconds
    public var currentPlaybackTime: Double {
        return currentTime
    }

    /// Get duration in seconds
    public var totalDuration: Double {
        return duration
    }

    // MARK: - Private

    private func setOption(_ name: String, value: String) {
        guard let handle = handle else { return }
        mpv_set_option_string(handle, name, value)
    }

    private func handleEvents() {
        eventQueue.async { [weak self] in
            guard let self = self, let handle = self.handle else { return }

            while true {
                guard let event = mpv_wait_event(handle, 0) else { break }
                let eventData = event.pointee

                if eventData.event_id == MPV_EVENT_NONE {
                    break
                }

                self.processEvent(eventData)
            }
        }
    }

    private func processEvent(_ event: mpv_event) {
        let eventName: String
        switch event.event_id {
        case MPV_EVENT_NONE: eventName = "MPV_EVENT_NONE"
        case MPV_EVENT_SHUTDOWN: eventName = "MPV_EVENT_SHUTDOWN"
        case MPV_EVENT_LOG_MESSAGE: eventName = "MPV_EVENT_LOG_MESSAGE"
        case MPV_EVENT_GET_PROPERTY_REPLY: eventName = "MPV_EVENT_GET_PROPERTY_REPLY"
        case MPV_EVENT_SET_PROPERTY_REPLY: eventName = "MPV_EVENT_SET_PROPERTY_REPLY"
        case MPV_EVENT_COMMAND_REPLY: eventName = "MPV_EVENT_COMMAND_REPLY"
        case MPV_EVENT_START_FILE: eventName = "MPV_EVENT_START_FILE"
        case MPV_EVENT_END_FILE: eventName = "MPV_EVENT_END_FILE"
        case MPV_EVENT_FILE_LOADED: eventName = "MPV_EVENT_FILE_LOADED"
        case MPV_EVENT_SEEK: eventName = "MPV_EVENT_SEEK"
        case MPV_EVENT_PLAYBACK_RESTART: eventName = "MPV_EVENT_PLAYBACK_RESTART"
        case MPV_EVENT_PROPERTY_CHANGE: eventName = "MPV_EVENT_PROPERTY_CHANGE"
        default: eventName = "UNKNOWN(\(event.event_id.rawValue))"
        }
        log("processEvent: \(eventName)")

        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            log("File loaded successfully")
            duration = getProperty("duration") ?? 0
            currentTime = 0
            log("Duration: \(duration)s")

            DispatchQueue.main.async { [weak self] in
                self?.state = .ready
                self?.onStateChanged?(.ready)
            }

        case MPV_EVENT_SEEK:
            isSeeking = true

        case MPV_EVENT_PLAYBACK_RESTART:
            isSeeking = false
            currentTime = getProperty("time-pos") ?? 0

        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)

        case MPV_EVENT_END_FILE:
            let reason = event.data.map { UnsafeRawPointer($0).load(as: mpv_end_file_reason.self) } ?? MPV_END_FILE_REASON_EOF
            log("END_FILE event, reason: \(reason.rawValue)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if reason == MPV_END_FILE_REASON_EOF {
                    self.log("Playback ended normally (EOF)")
                    self.state = .ended
                    self.onStateChanged?(.ended)
                } else if reason == MPV_END_FILE_REASON_ERROR {
                    let errorStruct = event.data.map { UnsafeRawPointer($0).assumingMemoryBound(to: mpv_event_end_file.self).pointee }
                    let errorCode = errorStruct?.error ?? 0
                    let errorStr = errorStruct.flatMap { String(cString: mpv_error_string($0.error)) } ?? "unknown"
                    self.log("Playback error: code=\(errorCode), message=\(errorStr)")
                    self.state = .error("Playback error: \(errorStr)")
                    self.onStateChanged?(.error("Playback error: \(errorStr)"))
                } else if reason == MPV_END_FILE_REASON_STOP {
                    self.log("Playback stopped")
                    self.state = .idle
                    self.onStateChanged?(.idle)
                } else if reason == MPV_END_FILE_REASON_QUIT {
                    self.log("Playback quit")
                    self.state = .idle
                    self.onStateChanged?(.idle)
                }
            }

        default:
            break
        }
    }

    private func handlePropertyChange(_ event: mpv_event) {
        guard let data = event.data else { return }
        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        let propertyName = String(cString: property.name)

        switch propertyName {
        case "time-pos":
            if let timePtr = property.data?.assumingMemoryBound(to: Double.self) {
                currentTime = timePtr.pointee

                if !isSeeking && duration > 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.onProgress?(self.currentTime, self.duration)
                    }
                }
            }

        case "duration":
            if let durationPtr = property.data?.assumingMemoryBound(to: Double.self) {
                duration = durationPtr.pointee
            }

        case "pause":
            if let pausePtr = property.data?.assumingMemoryBound(to: Bool.self) {
                let paused = pausePtr.pointee
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if paused && self.state == .playing {
                        self.state = .paused
                        self.onStateChanged?(.paused)
                    } else if !paused && self.state == .paused {
                        self.state = .playing
                        self.onStateChanged?(.playing)
                    }
                }
            }

        default:
            break
        }
    }

    private func getProperty(_ name: String) -> Double? {
        guard let handle = handle else { return nil }

        var value: Double = 0
        let result = mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)

        return result >= 0 ? value : nil
    }
}

// MARK: - MPVPlayerView

/// UIView subclass for mpv rendering
public class MPVPlayerView: UIView {
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    public override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
}
