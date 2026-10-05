// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import Foundation

/// Player state.
public enum PlayerState {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case error(Error)
}

/// Player engine that coordinates demuxer, decoders, and renderers.
public final class PlayerEngine {
    public private(set) var state: PlayerState = .idle

    private var demuxer: DemuxerPlugin?
    private var videoDecoder: VideoDecoderPlugin?
    private var audioDecoder: AudioDecoderPlugin?
    private var videoRenderer: VideoRenderer?
    private var audioRenderer: AudioRenderer?

    private var containerInfo: ContainerInfo?
    private var videoStreamIndex: Int?
    private var audioStreamIndex: Int?

    private var decodeQueue = DispatchQueue(label: "com.lunapeek.decode", qos: .userInteractive)
    private var isDecoding = false
    private var shouldStop = false

    public var videoRendererLayer: CALayer? {
        return videoRenderer?.layer
    }

    public init(
        demuxer: DemuxerPlugin,
        videoDecoder: VideoDecoderPlugin,
        audioDecoder: AudioDecoderPlugin,
        videoRenderer: VideoRenderer,
        audioRenderer: AudioRenderer
    ) {
        self.demuxer = demuxer
        self.videoDecoder = videoDecoder
        self.audioDecoder = audioDecoder
        self.videoRenderer = videoRenderer
        self.audioRenderer = audioRenderer
    }

    public func load(url: URL) async throws {
        state = .loading
        shouldStop = false

        guard let demuxer = demuxer else {
            throw PlayerError.noDemuxer
        }

        do {
            containerInfo = try await demuxer.open(url: url)
            identifyStreams()
            configureDecoders()
            state = .ready
        } catch {
            state = .error(error)
            throw error
        }
    }

    private func identifyStreams() {
        guard let containerInfo = containerInfo else { return }

        for stream in containerInfo.streams {
            if stream.codecType == .video && videoStreamIndex == nil {
                videoStreamIndex = stream.index
            } else if stream.codecType == .audio && audioStreamIndex == nil {
                audioStreamIndex = stream.index
            }
        }
    }

    private func configureDecoders() {
        guard let containerInfo = containerInfo else { return }

        for stream in containerInfo.streams {
            if stream.index == videoStreamIndex {
                Task {
                    try? await videoDecoder?.configure(with: stream.formatDescription)
                    videoRenderer?.configure(with: stream.formatDescription)
                }
            } else if stream.index == audioStreamIndex {
                Task {
                    try? await audioDecoder?.configure(with: stream.formatDescription)
                    audioRenderer?.configure(with: stream.formatDescription)
                }
            }
        }
    }

    public func play() {
        guard state == .ready || state == .paused else { return }

        state = .playing
        audioRenderer?.play()
        isDecoding = true
        startDecodeLoop()
    }

    private func startDecodeLoop() {
        decodeQueue.async { [weak self] in
            self?.decodeLoop()
        }
    }

    private func decodeLoop() {
        while isDecoding && !shouldStop {
            do {
                guard let packet = try demuxer?.readPacket() else {
                    DispatchQueue.main.async { [weak self] in
                        self?.state = .ended
                    }
                    break
                }

                Task { [weak self] in
                    await self?.processPacket(packet)
                }

                Thread.sleep(forTimeInterval: 0.001)
            } catch {
                print("Decode error: \(error)")
                break
            }
        }
    }

    private func processPacket(_ packet: MediaPacket) async {
        if packet.streamIndex == videoStreamIndex {
            do {
                let frames = try await videoDecoder?.decode(packet: packet) ?? []
                for frame in frames {
                    videoRenderer?.enqueue(frame)
                }
            } catch {
                print("Video decode error: \(error)")
            }
        } else if packet.streamIndex == audioStreamIndex {
            do {
                if let samples = try await audioDecoder?.decode(packet: packet) {
                    audioRenderer?.enqueue(samples)
                }
            } catch {
                print("Audio decode error: \(error)")
            }
        }
    }

    public func pause() {
        guard state == .playing else { return }

        state = .paused
        audioRenderer?.pause()
        isDecoding = false
    }

    public func stop() async {
        isDecoding = false
        shouldStop = true

        await demuxer?.close()
        await videoDecoder?.reset()
        await audioDecoder?.reset()
        videoRenderer?.reset()
        audioRenderer?.reset()

        state = .idle
    }

    public func seek(to timestamp: Int64) async throws {
        guard let demuxer = demuxer else { return }

        isDecoding = false
        try await demuxer.seek(to: timestamp)
        await videoDecoder?.flush()
        await audioDecoder?.flush()
        videoRenderer?.flush()
        audioRenderer?.flush()

        isDecoding = true
        startDecodeLoop()
    }
}

public enum PlayerError: Error {
    case noDemuxer
    case noDecoder
    case noRenderer
    case notReady
}
