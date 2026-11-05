// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

/// Thread-safe frame queue for producer-consumer pattern
public final class LPFrameQueue<T> {
    private var frames: [T] = []
    private let lock = NSLock()
    private let condition = NSCondition()
    private var maxSize: Int
    private var isFlushed = false

    public init(maxSize: Int = 30) {
        self.maxSize = maxSize
    }

    /// Push a frame to the queue
    /// Returns true if successful, false if queue is full and should wait
    public func push(_ frame: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        isFlushed = false

        if frames.count >= maxSize {
            return false
        }

        frames.append(frame)
        condition.signal()
        return true
    }

    /// Pop a frame from the queue
    /// If wait is true, blocks until a frame is available
    public func pop(wait: Bool) -> T? {
        lock.lock()
        defer { lock.unlock() }

        if wait {
            while frames.isEmpty && !isFlushed {
                condition.wait()
            }
        }

        if frames.isEmpty || isFlushed {
            return nil
        }

        return frames.removeFirst()
    }

    /// Peek at the first frame without removing it
    public func peek() -> T? {
        lock.lock()
        defer { lock.unlock()
        }
        return frames.first
    }

    /// Get current frame count
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    /// Check if queue is empty
    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return frames.isEmpty
    }

    /// Flush all frames and wake up any waiting threads
    public func flush() {
        lock.lock()
        defer { lock.unlock() }

        frames.removeAll()
        isFlushed = true
        condition.broadcast()
    }

    /// Clear flush state to allow queue to work again
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        frames.removeAll()
        isFlushed = false
    }
}
