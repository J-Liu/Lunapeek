// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
    static let profileChanged = Notification.Name("profileChanged")
}

/// Supported languages for the app
enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var displayName: String {
        switch self {
        case .system:
            return localizedStrings[.english]?["settings.language.system"] ?? "System Default"
        case .english:
            return localizedStrings[.english]?["settings.language.english"] ?? "English"
        case .simplifiedChinese:
            return localizedStrings[.simplifiedChinese]?["settings.language.simplifiedChinese"] ?? "简体中文"
        case .traditionalChinese:
            return localizedStrings[.traditionalChinese]?["settings.language.traditionalChinese"] ?? "繁體中文"
        }
    }
}

/// Manages app localization settings
final class LocalizationManager {
    static let shared = LocalizationManager()

    private let languageKey = "appLanguage"

    var currentLanguage: AppLanguage {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: languageKey),
               let language = AppLanguage(rawValue: rawValue) {
                return language
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    private init() {}

    func localizedString(_ key: String) -> String {
        let language = currentLanguage == .system ? systemLanguage() : currentLanguage
        return localizedStrings[language]?[key] ?? key
    }

    private func systemLanguage() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") {
            return .simplifiedChinese
        } else if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
            return .traditionalChinese
        }
        return .english
    }
}

/// Global helper for localized strings
func L(_ key: String) -> String {
    return LocalizationManager.shared.localizedString(key)
}

// MARK: - Localized Strings Dictionary

private let localizedStrings: [AppLanguage: [String: String]] = [
    .english: [
        // Settings tabs
        "settings.title": "Settings",
        "settings.tab.general": "General",
        "settings.tab.profile": "Profile",
        "settings.tab.devices": "Devices",
        "settings.tab.sound": "Sound",
        "settings.tab.colors": "Colors",
        "settings.tab.about": "About",

        // General
        "settings.theme": "Theme:",
        "settings.theme.system": "System Default",
        "settings.theme.light": "Light",
        "settings.theme.dark": "Dark",
        "settings.language": "Language:",
        "settings.language.system": "System Default",
        "settings.language.english": "English",
        "settings.language.simplifiedChinese": "Simplified Chinese",
        "settings.language.traditionalChinese": "Traditional Chinese",
        "settings.quitOnClose": "Close Window:",
        "settings.quitOnClose.checkbox": "Quit when closing window",
        "settings.voiceOutput": "Voice Output:",
        "settings.voiceOutput.checkbox": "Enable voice announcements",
        "settings.updateCheck": "Auto Update Check:",
        "settings.updateCheck.now": "Check Now",
        "settings.updateCheck.never": "Never",
        "settings.updateCheck.atStartup": "At Startup",
        "settings.updateCheck.daily": "Daily",
        "settings.updateCheck.weekly": "Weekly",
        "settings.updateCheck.monthly": "Monthly",

        // Profile
        "settings.profileName": "Profile Name:",
        "settings.rounds": "Rounds:",
        "settings.work": "Work Time:",
        "settings.rest": "Rest Time:",
        "settings.prepareTime": "Prepare Time:",
        "min": "min",
        "sec": "sec",
        "settings.warmUp": "Warm-up:",
        "settings.coolDown": "Cool-down:",

        // Sound
        "settings.sound.prepareCounting": "Prepare counting sound",
        "settings.sound.start": "Start sound",
        "settings.sound.endingNotify": "Ending notify sound",
        "settings.sound.end": "End sound",

        // Colors
        "settings.color.work": "Work",
        "settings.color.rest": "Rest",
        "settings.color.heartRate": "Heart Rate",
        "settings.color.prepare": "Prepare",
        "settings.color.warmUp": "Warm Up",
        "settings.color.coolDown": "Cool Down",
        "settings.color.reset": "Reset",

        // About
        "settings.about.version": "Version",
        "settings.about.copyright": "Copyright © 2026 Jia Liu",

        // Main Window
        "main.timer.ready": "READY",
        "main.timer.work": "WORK",
        "main.timer.rest": "REST",
        "main.work": "Work",
        "main.rest": "Rest",
        "main.warmUp": "Warm Up",
        "main.coolDown": "Cool Down",
        "main.finished": "Finished",
        "main.round": "Round %d",
        "main.button.go": "Go",
        "main.button.pause": "Pause",
        "main.button.resume": "Resume",
        "main.button.reset": "Reset",
        "main.button.settings": "Settings",
        "main.profile.select": "Select Profile",
        "main.heartRate.disconnected": "Disconnected",
        "main.heartRate.scanning": "Scanning…",
        "main.heartRate.connecting": "Connecting…",
        "Connecting": "Connecting",
        "main.error": "Error",

        // Menu
        "menu.about": "About %@",
        "menu.checkForUpdates": "Check for Updates...",
        "menu.quit": "Quit %@",
        "menu.hide": "Hide %@",
        "menu.hideOthers": "Hide Others",
        "menu.showAll": "Show All",
        "menu.file": "File",
        "menu.closeWindow": "Close Window",
        "menu.view": "View",
        "menu.enterFullScreen": "Enter Full Screen",
        "menu.window": "Window",
        "menu.minimize": "Minimize",
        "menu.zoom": "Zoom",
        "menu.bringAllToFront": "Bring All to Front",
        "menu.settings": "Settings...",

        // Devices
        "HRM Devices": "HRM Devices",
        "Scan Timeout": "Scan Timeout",
        "No heart rate devices found. Please make sure your device is powered on and nearby.": "No heart rate devices found. Please make sure your device is powered on and nearby.",
        "Scanning": "Scanning",
        "Looking for heart rate devices...": "Looking for heart rate devices...",
        "Connected": "Connected",
        "Connect": "Connect",
        "Disconnect": "Disconnect",
        "Set as Default": "Set as Default",
        "Remove": "Remove",
    ],

    .simplifiedChinese: [
        // Settings tabs
        "settings.title": "设置",
        "settings.tab.general": "通用",
        "settings.tab.profile": "配置",
        "settings.tab.devices": "设备",
        "settings.tab.sound": "声音",
        "settings.tab.colors": "颜色",
        "settings.tab.about": "关于",

        // General
        "settings.theme": "主题：",
        "settings.theme.system": "系统默认",
        "settings.theme.light": "浅色",
        "settings.theme.dark": "深色",
        "settings.language": "语言：",
        "settings.language.system": "系统默认",
        "settings.language.english": "English",
        "settings.language.simplifiedChinese": "简体中文",
        "settings.language.traditionalChinese": "繁體中文",
        "settings.quitOnClose": "关闭窗口：",
        "settings.quitOnClose.checkbox": "关闭窗口时退出应用",
        "settings.voiceOutput": "语音输出：",
        "settings.voiceOutput.checkbox": "启用语音播报",
        "settings.updateCheck": "自动检查更新：",
        "settings.updateCheck.now": "立即检查",
        "settings.updateCheck.never": "从不",
        "settings.updateCheck.atStartup": "每次启动",
        "settings.updateCheck.daily": "每天",
        "settings.updateCheck.weekly": "每周",
        "settings.updateCheck.monthly": "每月",

        // Profile
        "settings.profileName": "配置名称：",
        "settings.rounds": "回合数：",
        "settings.work": "训练时间：",
        "settings.rest": "休息时间：",
        "settings.prepareTime": "准备时间：",
        "min": "分",
        "sec": "秒",
        "settings.warmUp": "热身：",
        "settings.coolDown": "放松：",

        // Sound
        "settings.sound.prepareCounting": "准备倒计时声音",
        "settings.sound.start": "开始声音",
        "settings.sound.endingNotify": "即将结束提示音",
        "settings.sound.end": "结束声音",

        // Colors
        "settings.color.work": "训练",
        "settings.color.rest": "休息",
        "settings.color.heartRate": "心率",
        "settings.color.prepare": "准备",
        "settings.color.warmUp": "热身",
        "settings.color.coolDown": "放松",
        "settings.color.reset": "重置",

        // About
        "settings.about.version": "版本",
        "settings.about.copyright": "版权所有 © 2026 Jia Liu",

        // Main Window
        "main.timer.ready": "准备",
        "main.timer.work": "训练",
        "main.timer.rest": "休息",
        "main.work": "训练",
        "main.rest": "休息",
        "main.warmUp": "热身",
        "main.coolDown": "放松",
        "main.finished": "完成",
        "main.round": "第 %d 轮",
        "main.button.go": "开始",
        "main.button.pause": "暂停",
        "main.button.resume": "继续",
        "main.button.reset": "重置",
        "main.button.settings": "设置",
        "main.profile.select": "选择配置",
        "main.heartRate.disconnected": "未连接",
        "main.heartRate.scanning": "扫描中…",
        "main.heartRate.connecting": "连接中…",
        "Connecting": "连接中",
        "main.error": "错误",

        // Menu
        "menu.about": "关于 %@",
        "menu.checkForUpdates": "检查更新...",
        "menu.quit": "退出 %@",
        "menu.hide": "隐藏 %@",
        "menu.hideOthers": "隐藏其他",
        "menu.showAll": "全部显示",
        "menu.file": "文件",
        "menu.closeWindow": "关闭窗口",
        "menu.view": "显示",
        "menu.enterFullScreen": "进入全屏幕",
        "menu.window": "窗口",
        "menu.minimize": "最小化",
        "menu.zoom": "缩放",
        "menu.bringAllToFront": "全部移到最前",
        "menu.settings": "设置...",

        // Devices
        "HRM Devices": "心率设备",
        "Scan Timeout": "扫描超时",
        "No heart rate devices found. Please make sure your device is powered on and nearby.": "未找到心率设备。请确保设备已开机且在附近。",
        "Scanning": "扫描中",
        "Looking for heart rate devices...": "正在搜索心率设备...",
        "Connected": "已连接",
        "Connect": "连接",
        "Disconnect": "断开",
        "Set as Default": "设为默认",
        "Remove": "移除",
    ],

    .traditionalChinese: [
        // Settings tabs
        "settings.title": "設定",
        "settings.tab.general": "一般",
        "settings.tab.profile": "設定檔",
        "settings.tab.devices": "裝置",
        "settings.tab.sound": "聲音",
        "settings.tab.colors": "顏色",
        "settings.tab.about": "關於",

        // General
        "settings.theme": "主題：",
        "settings.theme.system": "系統預設",
        "settings.theme.light": "淺色",
        "settings.theme.dark": "深色",
        "settings.language": "語言：",
        "settings.language.system": "系統預設",
        "settings.language.english": "English",
        "settings.language.simplifiedChinese": "简体中文",
        "settings.language.traditionalChinese": "繁體中文",
        "settings.quitOnClose": "關閉視窗：",
        "settings.quitOnClose.checkbox": "關閉視窗時退出應用程式",
        "settings.voiceOutput": "語音輸出：",
        "settings.voiceOutput.checkbox": "啟用語音播報",
        "settings.updateCheck": "自動檢查更新：",
        "settings.updateCheck.now": "立即檢查",
        "settings.updateCheck.never": "從不",
        "settings.updateCheck.atStartup": "每次啟動",
        "settings.updateCheck.daily": "每天",
        "settings.updateCheck.weekly": "每週",
        "settings.updateCheck.monthly": "每月",

        // Profile
        "settings.profileName": "設定檔名稱：",
        "settings.rounds": "回合數：",
        "settings.work": "訓練時間：",
        "settings.rest": "休息時間：",
        "settings.prepareTime": "準備時間：",
        "min": "分",
        "sec": "秒",
        "settings.warmUp": "熱身：",
        "settings.coolDown": "放鬆：",

        // Sound
        "settings.sound.prepareCounting": "準備倒數聲音",
        "settings.sound.start": "開始聲音",
        "settings.sound.endingNotify": "即將結束提示音",
        "settings.sound.end": "結束聲音",

        // Colors
        "settings.color.work": "訓練",
        "settings.color.rest": "休息",
        "settings.color.heartRate": "心率",
        "settings.color.prepare": "準備",
        "settings.color.warmUp": "熱身",
        "settings.color.coolDown": "放鬆",
        "settings.color.reset": "重設",

        // About
        "settings.about.version": "版本",
        "settings.about.copyright": "版權所有 © 2026 Jia Liu",

        // Main Window
        "main.timer.ready": "準備",
        "main.timer.work": "訓練",
        "main.timer.rest": "休息",
        "main.work": "訓練",
        "main.rest": "休息",
        "main.warmUp": "熱身",
        "main.coolDown": "放鬆",
        "main.finished": "完成",
        "main.round": "第 %d 輪",
        "main.button.go": "開始",
        "main.button.pause": "暫停",
        "main.button.resume": "繼續",
        "main.button.reset": "重設",
        "main.button.settings": "設定",
        "main.profile.select": "選擇設定檔",
        "main.heartRate.disconnected": "未連線",
        "main.heartRate.scanning": "掃描中…",
        "main.heartRate.connecting": "連線中…",
        "Connecting": "連線中",
        "main.error": "錯誤",

        // Menu
        "menu.about": "關於 %@",
        "menu.checkForUpdates": "檢查更新...",
        "menu.quit": "結束 %@",
        "menu.hide": "隱藏 %@",
        "menu.hideOthers": "隱藏其他",
        "menu.showAll": "全部顯示",
        "menu.file": "檔案",
        "menu.closeWindow": "關閉視窗",
        "menu.view": "顯示",
        "menu.enterFullScreen": "進入全螢幕",
        "menu.window": "視窗",
        "menu.minimize": "最小化",
        "menu.zoom": "縮放",
        "menu.bringAllToFront": "全部移到最前",
        "menu.settings": "設定...",

        // Devices
        "HRM Devices": "心率裝置",
        "Scan Timeout": "掃描逾時",
        "No heart rate devices found. Please make sure your device is powered on and nearby.": "未找到心率裝置。請確保裝置已開機且在附近。",
        "Scanning": "掃描中",
        "Looking for heart rate devices...": "正在搜尋心率裝置...",
        "Connected": "已連線",
        "Connect": "連線",
        "Disconnect": "斷開",
        "Set as Default": "設為預設",
        "Remove": "移除",
    ]
]
