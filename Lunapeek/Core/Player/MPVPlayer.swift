// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import Mpv

/// Player state
public enum MPVPlayerState {
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

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?

    private var url: URL?
    private var duration: Double = 0
    private var currentTime: Double = 0

    private var eventQueue = DispatchQueue(label: "com.lunapeek.mpv.events")
    private var isSeeking = false

    public init() {}

    deinit {
        close()
    }

    // MARK: - Public API

    /// Open a file URL
    public func open(url: URL) {
        self.url = url
        state = .loading
        onStateChanged?(.loading)

        // Create mpv handle
        handle = mpv_create()
        guard let handle = handle else {
            state = .error("Failed to create mpv handle")
            onStateChanged?(.error("Failed to create mpv handle"))
            return
        }

        // Set options
        setOption("hwdec", value: "auto")
        setOption("vo", value: "libmpv")
        setOption("vid", value: "auto")
        setOption("aid", value: "auto")

        // Initialize
        let initResult = mpv_initialize(handle)
        guard initResult >= 0 else {
            let error = String(cString: mpv_error_string(initResult))
            state = .error("mpv_initialize failed: \(error)")
            onStateChanged?(.error("mpv_initialize failed: \(error)"))
            mpv_destroy(handle)
            self.handle = nil
            return
        }

        // Set up event callback
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx = ctx else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(ctx).takeUnretainedValue()
            player.handleEvents()
        }, Unmanaged.passUnretained(self).toOpaque())

        // Load file
        var args = [url.path, UnsafeMutablePointer<CChar>(mutating: nil)]
        let result = mpv_command(handle, &args)

        if result < 0 {
            let error = String(cString: mpv_error_string(result))
            state = .error("Failed to load file: \(error)")
            onStateChanged?(.error("Failed to load file: \(error)"))
            close()
        }
    }

    /// Play
    public func play() {
        guard let handle = handle, state == .ready || state == .paused else { return }

        var pause: Int64 = 0
        mpv_set_option(handle, "pause", MPV_FORMAT_INT64, &pause)

        state = .playing
        onStateChanged?(.playing)
    }

    /// Pause
    public func pause() {
        guard let handle = handle, state == .playing else { return }

        var pause: Int64 = 1
        mpv_set_option(handle, "pause", MPV_FORMAT_INT64, &pause)

        state = .paused
        onStateChanged?(.paused)
    }

    /// Seek to timestamp (seconds)
    public func seek(to time: Double) {
        guard let handle = handle else { return }

        isSeeking = true
        let timeStr = String(format: "%.2f", time)
        let absolute = "absolute"

        var args: [UnsafeMutablePointer<CChar>?] = [
            strdup("seek"),
            strdup(timeStr),
            strdup(absolute),
            nil
        ]

        mpv_command_async(handle, 0, &args)

        // Free allocated strings
        for i in 0..<3 {
            free(args[i])
        }
    }

    /// Stop and close
    public func close() {
        if let renderContext = renderContext {
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }

        if let handle = handle {
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
                let event = mpv_wait_event(handle, 0)
                guard let eventData = event?.pointee else { break }

                if eventData.event_id == MPV_EVENT_NONE {
                    break
                }

                self.processEvent(eventData)
            }
        }
    }

    private func processEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            // File loaded successfully
            duration = getProperty("duration") ?? 0
            currentTime = 0

            DispatchQueue.main.async { [weak self] in
                self?.state = .ready
                self?.onStateChanged?(.ready)
            }

        case MPV_EVENT_SEEK:
            isSeeking = true

        case MPV_EVENT_PLAYBACK_RESTART:
            isSeeking = false
            // Update current time after seek
            currentTime = getProperty("time-pos") ?? 0

        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)

        case MPV_EVENT_END_FILE:
            let reason = event.data?.load(as: mpv_end_file_reason.self) ?? MPV_END_FILE_REASON_EOF
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if reason == MPV_END_FILE_REASON_EOF {
                    self.state = .ended
                    self.onStateChanged?(.ended)
                } else if reason == MPV_END_FILE_REASON_ERROR {
                    self.state = .error("Playback error")
                    self.onStateChanged?(.error("Playback error"))
                }
            }

        default:
            break
        }
    }

    private func handlePropertyChange(_ event: mpv_event) {
        guard let data = event.data?.load(as: mpv_event_property.self) else { return }

        let propertyName = String(cString: data.name)

        switch propertyName {
        case "time-pos":
            if let time = UnsafePointer<Double>(OpaquePointer(data.data))?.pointee {
                currentTime = time

                if !isSeeking && duration > 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.onProgress?(self.currentTime, self.duration)
                    }
                }
            }

        case "pause":
            if let paused = UnsafePointer<Bool>(OpaquePointer(data.data))?.pointee {
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

    private func observeProperties() {
        guard let handle = handle else { return }

        // Observe time position
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        // Observe pause state
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
    }
}
