// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import ActivityKit

struct LunapeekWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String           // 文件名
        var duration: Double        // 总时长（秒）
        var currentTime: Double     // 当前播放时间
        var isPlaying: Bool         // 是否正在播放
        var fileSize: String        // 文件大小
        var isVideo: Bool           // 是否是视频
        var thumbnailData: Data?    // 视频缩略图数据
    }

    var name: String
}
