// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation

/// FFmpeg-based demuxer supporting MKV, FLV, TS and other containers.
/// This is a placeholder implementation until FFmpeg is integrated.
public final class FFmpegDemuxerPlugin: DemuxerPlugin {
    private var isOpen = false
    private var containerInfo: ContainerInfo?

    public init() {}

    public func open(url: URL) async throws -> ContainerInfo {
        guard FFmpegDemuxerPlugin.supports(url: url) else {
            throw DemuxerError.failedToLoadTracks
        }

        // TODO: Implement with FFmpeg avformat_open_input
        // For now, return placeholder info
        isOpen = true
        containerInfo = ContainerInfo(
            duration: 0,
            bitRate: 0,
            streams: []
        )
        return containerInfo!
    }

    public func readPacket() async throws -> MediaPacket? {
        guard isOpen else {
            throw DemuxerError.noAsset
        }

        // TODO: Implement with FFmpeg av_read_frame
        return nil
    }

    public func seek(to timestamp: Int64) async throws {
        guard isOpen else {
            throw DemuxerError.noAsset
        }

        // TODO: Implement with FFmpeg av_seek_frame
    }

    public func close() async {
        isOpen = false
        containerInfo = nil
    }

    public static func supports(url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        let supportedFormats = [
            "mkv", "webm", "flv", "ts", "mts", "m2ts",
            "avi", "wmv", "asf", "rm", "rmvb",
            "mp4", "mov", "m4v", "3gp",
            "mp3", "flac", "ogg", "wav", "aac"
        ]
        return supportedFormats.contains(pathExtension)
    }
}