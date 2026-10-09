// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

/// Simple log manager for debugging
final class LogManager {
    static let shared = LogManager()

    private(set) var logs: [String] = []
    private let lock = NSLock()
    var handler: ((String) -> Void)?

    private init() {}

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"

        lock.lock()
        logs.append(entry)
        if logs.count > 100 { logs.removeFirst() }
        lock.unlock()

        handler?(entry)
        print(message)
    }

    func clear() {
        lock.lock()
        logs.removeAll()
        lock.unlock()
    }
}

func debugLog(_ message: String) {
    LogManager.shared.log(message)
}
