// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation

/// Factory for creating appropriate demuxer based on URL.
public struct DemuxerFactory {
    public static func createDemuxer(for url: URL) -> DemuxerPlugin {
        let scheme = url.scheme?.lowercased()

        // Network protocols use FFmpeg demuxer
        if let scheme = scheme, ["sftp", "smb", "http", "https", "rtmp", "rtsp"].contains(scheme) {
            return FFmpegDemuxerPlugin()
        }

        // Local files: prefer system demuxer, fallback to FFmpeg
        let pathExtension = url.pathExtension.lowercased()
        let systemSupported = ["mp4", "mov", "m4v", "3gp"]

        if systemSupported.contains(pathExtension) {
            return SystemDemuxerPlugin()
        }

        // Other formats require FFmpeg
        return FFmpegDemuxerPlugin()
    }

    public static func isNetworkStream(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["sftp", "smb", "http", "https", "rtmp", "rtsp"].contains(scheme)
    }
}