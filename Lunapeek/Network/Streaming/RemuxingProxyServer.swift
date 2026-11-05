// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import Network
import os

/// HTTP proxy server that remuxes MKV/WebM/AVI to MP4 on-the-fly.
/// Used for both local and network files that need format conversion.
final class RemuxingProxyServer: @unchecked Sendable {
    private var listener: NWListener?
    private var _port: OSAllocatedUnfairLock<UInt16> = OSAllocatedUnfairLock(initialState: 0)
    private let queue = DispatchQueue(label: "com.lunapeek.remux-proxy")
    private var isRunning = false

    // Active connections
    private var activeConnections: OSAllocatedUnfairLock<[NWConnection]> = OSAllocatedUnfairLock(initialState: [])

    // Data source
    private var fileName: String = ""
    private var fileSize: Int64 = 0
    private var dataReader: ((Int64, Int) throws -> Data)?  // Synchronous
    private var logHandler: ((String) -> Void)?

    // Remuxer
    private var remuxer: FFmpegRemuxer?
    private var remuxerDelegate: RemuxingDelegate?
    private var remuxedData: OSAllocatedUnfairLock<Data> = OSAllocatedUnfairLock(initialState: Data())
    private var remuxCompleted: OSAllocatedUnfairLock<Bool> = OSAllocatedUnfairLock(initialState: false)
    private var remuxError: OSAllocatedUnfairLock<Error?> = OSAllocatedUnfairLock(initialState: nil)

    var localURL: URL? {
        let port = _port.withLock { $0 }
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/remuxed.mp4")
    }

    private func log(_ message: String) {
        debugLog("🔄 \(message)")
    }

    /// Start the proxy server with remuxing.
    /// - Parameters:
    ///   - fileName: Original file name
    ///   - fileSize: Total file size
    ///   - reader: Synchronous function to read data from offset
    ///   - logHandler: Optional callback for log messages
    func start(
        fileName: String,
        fileSize: Int64,
        reader: @escaping (Int64, Int) throws -> Data,
        logHandler: ((String) -> Void)? = nil
    ) async throws {
        self.fileName = fileName
        self.fileSize = fileSize
        self.dataReader = reader
        self.logHandler = logHandler

        // Start HTTP server FIRST, then remuxer
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: .any)
        let weakListener = listener
        let weakPort = _port
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = weakListener?.port?.rawValue {
                    weakPort.withLock { $0 = port }
                    debugLog("🔄 ===== SERVER READY on port \(port) =====")
                }
            case .failed(let error):
                debugLog("🔄 Server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            debugLog("🔄 New connection received")
            self?.handleConnection(connection)
        }

        isRunning = true
        listener?.start(queue: queue)

        // Wait for server to be ready
        debugLog("🔄 Waiting for server to be ready...")
        var serverWaitAttempts = 0
        while true {
            let currentPort = _port.withLock { $0 }
            if currentPort > 0 {
                debugLog("🔄 Server ready on port \(currentPort)")
                break
            }
            serverWaitAttempts += 1
            if serverWaitAttempts > 100 {
                throw NSError(domain: "ServerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server failed to start"])
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Start remuxer AFTER server is ready
        await startRemuxer()

        // Wait for remuxer to generate initial data (at least 50KB)
        // This ensures AVPlayer gets data immediately on first request
        debugLog("🔄 Waiting for remuxer to generate initial data")
        let minInitialData: Int64 = 50 * 1024  // 50KB
        var waitAttempts = 0
        let maxWaitAttempts = 100  // 10 seconds max

        while getRemuxedSize() < minInitialData && !isRemuxComplete() && waitAttempts < maxWaitAttempts {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            waitAttempts += 1
            if waitAttempts % 10 == 0 {
                debugLog("🔄 Remuxer progress: \(getRemuxedSize()) bytes, waiting...")
            }
        }

        if let error = remuxError.withLock({ $0 }) {
            debugLog("🔄 Remuxer failed during startup: \(error)")
            throw error
        }

        let dataSize = getRemuxedSize()
        debugLog("🔄 Remuxer ready with \(dataSize) bytes after \(waitAttempts * 100)ms")
    }

    func stop() {
        isRunning = false

        // Stop remuxer
        remuxer?.stop()
        remuxer = nil
        remuxerDelegate = nil

        // Cancel all connections
        let connections = activeConnections.withLock {
            let conns = $0
            $0.removeAll()
            return conns
        }

        for connection in connections {
            connection.cancel()
        }

        listener?.cancel()
        listener = nil
        _port.withLock { $0 = 0 }
        dataReader = nil
    }

    private func startRemuxer() async {
        guard let reader = dataReader else { return }

        remuxer = FFmpegRemuxer()

        // Create delegate to collect remuxed data - MUST store it to prevent deallocation
        remuxerDelegate = RemuxingDelegate { [weak self] data in
            self?.appendRemuxedData(data)
        } onComplete: { [weak self] error in
            self?.remuxCompleted.withLock { $0 = true }
            self?.remuxError.withLock { $0 = error }
            if let error = error {
                self?.log("Remux failed: \(error)")
            } else {
                self?.log("Remux completed")
            }
        }

        // Start remuxing
        remuxer?.start(
            fileName: fileName,
            fileSize: fileSize,
            readCallback: reader,
            delegate: remuxerDelegate!
        )
    }

    private func appendRemuxedData(_ data: Data) {
        remuxedData.withLock { $0.append(data) }
        // Only log every 10MB to reduce log noise
        let newSize = getRemuxedSize()
        if newSize % (10 * 1024 * 1024) < data.count {
            debugLog("🔄 Remuxed: \(newSize / 1024 / 1024) MB")
        }
    }

    private func getRemuxedData(at offset: Int64, length: Int) -> Data {
        remuxedData.withLock { buffer in
            let totalSize = buffer.count
            guard offset < totalSize else {
                return Data()
            }
            let start = Int(offset)
            let end = min(start + length, totalSize)
            return buffer.subdata(in: start..<end)
        }
    }

    private func getRemuxedSize() -> Int64 {
        Int64(remuxedData.withLock { $0.count })
    }

    private func isRemuxComplete() -> Bool {
        remuxCompleted.withLock { $0 }
    }

    private func restartRemuxer(atOffset offset: Int64) async {
        // Stop current remuxer
        remuxer?.stop()

        // Clear buffer
        remuxedData.withLock { $0 = Data() }
        remuxCompleted.withLock { $0 = false }
        remuxError.withLock { $0 = nil }

        // Restart remuxer
        await startRemuxer()

        // Wait for some data
        var attempts = 0
        while getRemuxedSize() < 65536 && !isRemuxComplete() && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
    }

    private nonisolated func handleConnection(_ connection: NWConnection) {
        debugLog("🔄 handleConnection: new connection")
        connection.start(queue: queue)
        readNextRequest(connection: connection)
    }

    private nonisolated func readNextRequest(connection: NWConnection) {
        debugLog("🔄 readNextRequest: waiting for data")
        var buffer = Data()

        func receiveLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    debugLog("🔄 readNextRequest: received \(data.count) bytes")
                    buffer.append(data)

                    if let requestString = String(data: buffer, encoding: .utf8),
                       requestString.contains("\r\n\r\n") {
                        debugLog("🔄 readNextRequest: complete request received")
                        self?.handleRequest(requestString, connection: connection) {
                            self?.readNextRequest(connection: connection)
                        }
                        return
                    }

                    receiveLoop()
                }

                if isComplete || error != nil {
                    debugLog("🔄 readNextRequest: connection closed, isComplete=\(isComplete), error=\(error?.localizedDescription ?? "none")")
                    connection.cancel()
                }
            }
        }

        receiveLoop()
    }

    private nonisolated func handleRequest(_ request: String, connection: NWConnection, completion: @escaping () -> Void) {
        debugLog("🔄 ========== HTTP REQUEST ==========")
        debugLog("🔄 \(request.prefix(200))")

        let lines = request.split(separator: "\r\n")
        guard let requestLine = lines.first else {
            sendError(connection: connection, code: 400, message: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 3 else {
            sendError(connection: connection, code: 400, message: "Bad Request")
            return
        }

        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            sendError(connection: connection, code: 405, message: "Method Not Allowed")
            return
        }

        // Parse Range header
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = Int64.max
        var isRangeRequest = false

        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                isRangeRequest = true
                let rangeValue = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if let range = parseRangeHeader(rangeValue) {
                    rangeStart = range.start
                    rangeEnd = range.end
                }
            }
        }

        // Process request synchronously - all data access is thread-safe via locks
        processRequestSynchronous(
            connection: connection,
            method: method,
            isRangeRequest: isRangeRequest,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            completion: completion
        )
    }

    private nonisolated func processRequestSynchronous(
        connection: NWConnection,
        method: String,
        isRangeRequest: Bool,
        rangeStart: Int64,
        rangeEnd: Int64,
        completion: @escaping () -> Void
    ) {
        // For probe requests (0-1), only need a small amount
        let minRequired = isRangeRequest && rangeEnd <= 1 ? Int64(2) : Int64(65536)

        // Check if data is already available (non-blocking)
        let currentSize = getRemuxedSize()
        debugLog("🔄 Current buffer size: \(currentSize), requested: \(rangeStart)-\(rangeEnd), minRequired: \(minRequired)")

        // Check for errors
        if let error = remuxError.withLock({ $0 }) {
            debugLog("🔄 Remux error: \(error)")
            sendError(connection: connection, code: 500, message: "Remux failed: \(error.localizedDescription)")
            completion()
            return
        }

        // If not enough data and remux is still in progress, return 503
        // AVPlayer will retry automatically
        guard currentSize >= minRequired || isRemuxComplete() else {
            debugLog("🔄 Not enough data yet, returning 503 (will retry)")
            sendError(connection: connection, code: 503, message: "Service Unavailable")
            completion()
            return
        }

        if method == "HEAD" {
            let headers = buildHeaders(
                statusCode: 200,
                contentLength: currentSize,
                acceptRanges: "bytes",
                contentType: "video/mp4"
            )
            sendResponse(connection: connection, headers: headers)
            completion()
            return
        }

        // Calculate actual range end based on available data
        let actualEndOffset = currentSize > 0 ? min(rangeEnd, currentSize - 1) : rangeEnd
        let contentLength = currentSize > 0 ? max(0, actualEndOffset - rangeStart + 1) : 0

        guard contentLength > 0, currentSize > rangeStart else {
            // No data yet
            debugLog("🔄 No data available: currentSize=\(currentSize), rangeStart=\(rangeStart)")
            sendError(connection: connection, code: 503, message: "Service Unavailable")
            completion()
            return
        }

        let data = getRemuxedData(at: rangeStart, length: Int(contentLength))
        let endOffset = rangeStart + contentLength - 1

        // Build headers
        // For Range requests, use 206 Partial Content with Content-Range
        // This is required for AVPlayer to properly handle the stream
        let headers: String
        if isRangeRequest {
            let contentRange = "bytes \(rangeStart)-\(endOffset)/\(currentSize)"
            headers = buildHeaders(
                statusCode: 206,
                contentLength: contentLength,
                acceptRanges: "bytes",
                contentType: "video/mp4",
                contentRange: contentRange
            )
        } else {
            headers = buildHeaders(
                statusCode: 200,
                contentLength: currentSize,
                acceptRanges: "bytes",
                contentType: "video/mp4"
            )
        }

        debugLog("🔄 Response: \(contentLength) bytes")
        sendResponse(connection: connection, headers: headers, body: data)
        completion()
    }

    private nonisolated func parseRangeHeader(_ value: String) -> (start: Int64, end: Int64)? {
        guard value.hasPrefix("bytes=") else { return nil }
        let rangeStr = String(value.dropFirst(6))

        if rangeStr.contains("-") {
            let parts = rangeStr.split(separator: "-")
            if let startStr = parts.first, let start = Int64(startStr) {
                let end: Int64
                if parts.count > 1, let endVal = Int64(parts[1]) {
                    end = endVal
                } else {
                    end = Int64.max // Will be clamped later
                }
                return (start, end)
            }
        }

        return nil
    }

    private nonisolated func buildHeaders(
        statusCode: Int,
        contentLength: Int64,
        acceptRanges: String?,
        contentType: String,
        contentRange: String? = nil
    ) -> String {
        var headers = "HTTP/1.1 \(statusCode) \(statusMessage(for: statusCode))\r\n"
        headers += "Content-Length: \(contentLength)\r\n"
        if let acceptRanges = acceptRanges {
            headers += "Accept-Ranges: \(acceptRanges)\r\n"
        }
        headers += "Content-Type: \(contentType)\r\n"
        if let contentRange = contentRange {
            headers += "Content-Range: \(contentRange)\r\n"
        }
        headers += "Cache-Control: no-cache\r\n"
        headers += "\r\n"
        return headers
    }

    private nonisolated func statusMessage(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }

    private nonisolated func sendResponse(connection: NWConnection, headers: String, body: Data? = nil) {
        var data = Data(headers.utf8)
        if let body = body {
            data.append(body)
        }
        debugLog("🔄 Sending response: \(data.count) bytes")
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                debugLog("🔄 Send error: \(error)")
            }
        })
    }

    private nonisolated func sendError(connection: NWConnection, code: Int, message: String) {
        let body = "<html><body><h1>\(code) \(message)</h1></body></html>"
        let headers = "HTTP/1.1 \(code) \(message)\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
        sendResponse(connection: connection, headers: headers, body: Data(body.utf8))
    }
}

// MARK: - Remuxer Delegate

private class RemuxingDelegate: RemuxerOutputDelegate {
    private let onData: (Data) -> Void
    private let onComplete: (Error?) -> Void

    init(onData: @escaping (Data) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.onData = onData
        self.onComplete = onComplete
    }

    func remuxerDidOutputData(_ data: Data) {
        onData(data)
    }

    func remuxerDidComplete(error: Error?) {
        onComplete(error)
    }
}
