// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

/// Factory for creating appropriate demuxer based on URL.
public struct DemuxerFactory {
    /// Formats that can be played natively by iOS AVPlayer
    private static let nativeFormats = ["mp4", "mov", "m4v", "3gp"]

    /// Formats that need remuxing to MP4
    private static let remuxFormats = ["mkv", "webm", "avi", "wmv", "asf", "flv", "ts", "mts", "m2ts"]

    /// Check if a format needs remuxing
    public static func needsRemux(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return remuxFormats.contains(ext)
    }

    /// Check if a format is natively supported
    public static func isNativeFormat(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return nativeFormats.contains(ext)
    }

    public static func createDemuxer(for url: URL) -> DemuxerPlugin {
        // For MP4/MOV files (local or via HTTP proxy), use SystemDemuxerPlugin
        if isNativeFormat(url) {
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
