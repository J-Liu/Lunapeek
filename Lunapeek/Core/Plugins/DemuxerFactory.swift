// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

/// Factory for creating appropriate demuxer based on URL.
public struct DemuxerFactory {
    public static func createDemuxer(for url: URL) -> DemuxerPlugin {
        let pathExtension = url.pathExtension.lowercased()
        let systemSupported = ["mp4", "mov", "m4v", "3gp"]

        // For MP4/MOV files (local or via HTTP proxy), use SystemDemuxerPlugin
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
