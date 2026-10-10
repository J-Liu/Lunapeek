// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

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

struct LunapeekWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LunapeekWidgetAttributes.self) { context in
            // Lock screen/banner UI
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        if context.state.isVideo, let data = context.state.thumbnailData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 30))
                                .foregroundColor(.green)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(context.state.fileSize)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * CGFloat(context.state.currentTime / context.state.duration), height: 6)
                            }
                        }
                        .frame(height: 6)

                        // Time labels
                        HStack {
                            Text(formatTime(context.state.currentTime))
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formatTime(context.state.duration))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        // Control buttons
                        HStack(spacing: 30) {
                            // Fast backward
                            Button(intent: FastBackwardIntent()) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            // Play/Pause
                            Button(intent: PlayPauseIntent()) {
                                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            // Fast forward
                            Button(intent: FastForwardIntent()) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            // Route picker
                            Button(intent: RoutePickerIntent()) {
                                Image(systemName: "airplayaudio")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                // Compact leading - show thumbnail or icon
                if context.state.isVideo, let data = context.state.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .foregroundColor(.green)
                }
            } compactTrailing: {
                // Compact trailing - show time
                Text(formatTime(context.state.currentTime))
                    .font(.caption2)
                    .foregroundColor(.white)
            } minimal: {
                // Minimal - just show play state
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                    .foregroundColor(.green)
            }
            .widgetURL(URL(string: "lunapeek://player"))
            .keylineTint(Color.green)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// Lock screen view
struct LockScreenView: View {
    let state: LunapeekWidgetAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            // Top: thumbnail + filename + file size
            HStack(spacing: 12) {
                // Thumbnail or audio icon
                if state.isVideo, let data = state.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 60, height: 45)
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(state.fileSize)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()
            }

            // Middle: progress bar with time
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(state.currentTime / state.duration), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(formatTime(state.currentTime))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(formatTime(state.duration))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            // Bottom: control buttons
            HStack(spacing: 40) {
                // Fast backward
                Button(intent: FastBackwardIntent()) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                // Play/Pause (larger)
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                // Fast forward
                Button(intent: FastForwardIntent()) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                // Route picker
                Button(intent: RoutePickerIntent()) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// App Intents for buttons

struct PlayPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play/Pause"

    func perform() async throws -> some IntentResult {
        // This will be handled by the main app via notification
        return .result()
    }
}

struct FastForwardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Fast Forward"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct FastBackwardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Fast Backward"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct RoutePickerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Route Picker"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

extension LunapeekWidgetAttributes {
    fileprivate static var preview: LunapeekWidgetAttributes {
        LunapeekWidgetAttributes(name: "Preview")
    }
}

extension LunapeekWidgetAttributes.ContentState {
    fileprivate static var sample: LunapeekWidgetAttributes.ContentState {
        LunapeekWidgetAttributes.ContentState(
            title: "Sample Video.mp4",
            duration: 180.0,
            currentTime: 45.0,
            isPlaying: true,
            fileSize: "25.3 MB",
            isVideo: true,
            thumbnailData: nil
        )
    }
}

#Preview("Notification", as: .content, using: LunapeekWidgetAttributes.preview) {
   LunapeekWidgetLiveActivity()
} contentStates: {
    LunapeekWidgetAttributes.ContentState.sample
}
