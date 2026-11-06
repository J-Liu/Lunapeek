// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

/// Manages playback progress history for media files.
/// Each file has at most one record - the last exit position.
final class PlaybackHistory {
    static let shared = PlaybackHistory()

    private let defaults = UserDefaults.standard
    private let key = "playbackHistory"

    private init() {}

    // MARK: - Public API

    /// Save playback progress for a file.
    /// - Parameters:
    ///   - url: The file URL
    ///   - time: The playback time in seconds
    func saveProgress(for url: URL, time: Double) {
        var history = loadHistory()
        let key = url.absoluteString
        history[key] = time
        defaults.set(history, forKey: self.key)
    }

    /// Get playback progress for a file.
    /// - Parameter url: The file URL
    /// - Returns: The saved playback time in seconds, or nil if no record exists
    func getProgress(for url: URL) -> Double? {
        let history = loadHistory()
        let key = url.absoluteString
        return history[key]
    }

    /// Remove playback record for a file.
    /// - Parameter url: The file URL
    func removeProgress(for url: URL) {
        var history = loadHistory()
        let key = url.absoluteString
        history.removeValue(forKey: key)
        defaults.set(history, forKey: self.key)
    }

    /// Clean up records for files that no longer exist.
    /// Call this periodically (e.g., when playing any file).
    func cleanupOrphanedRecords() {
        var history = loadHistory()
        var cleaned = false

        for (key, _) in history {
            guard let url = URL(string: key) else {
                history.removeValue(forKey: key)
                cleaned = true
                continue
            }

            // Check if file exists
            if !FileManager.default.fileExists(atPath: url.path) {
                history.removeValue(forKey: key)
                cleaned = true
            }
        }

        if cleaned {
            defaults.set(history, forKey: self.key)
        }
    }

    // MARK: - Private

    private func loadHistory() -> [String: Double] {
        return defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
