// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import os

/// Simple log manager for debugging
final class LogManager: @unchecked Sendable {
    static let shared: LogManager = LogManager()

    private var logs: OSAllocatedUnfairLock<[String]> = OSAllocatedUnfairLock(initialState: [])
    private var handler: OSAllocatedUnfairLock<((String) -> Void)?> = OSAllocatedUnfairLock(initialState: nil)
    private var logFile: OSAllocatedUnfairLock<URL?> = OSAllocatedUnfairLock(initialState: nil)

    private init() {}

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"

        logs.withLock {
            $0.append(entry)
            if $0.count > 100 { $0.removeFirst() }
        }

        // Capture handler outside of lock to avoid potential issues
        let capturedHandler = handler.withLock { $0 }

        // Call handler on main queue to avoid threading issues
        if let handler = capturedHandler {
            DispatchQueue.main.async {
                handler(entry)
            }
        }

        print(message)

        // Also write to file for crash debugging
        writeToFile(entry)
    }

    func clear() {
        logs.withLock { $0.removeAll() }
    }

    func setHandler(_ newHandler: ((String) -> Void)?) {
        handler.withLock { $0 = newHandler }
    }

    func setLogFile(_ url: URL) {
        logFile.withLock { $0 = url }
    }

    private func writeToFile(_ entry: String) {
        guard let url = logFile.withLock({ $0 }) else { return }
        let line = entry + "\n"
        guard let data = line.data(using: .utf8) else { return }
        // Append to file
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

nonisolated func debugLog(_ message: String) {
    DispatchQueue.main.async {
        LogManager.shared.log(message)
    }
}
