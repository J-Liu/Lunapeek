// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import Network

/// HTTP proxy server that remuxes MKV/WebM/AVI to MP4 on-the-fly.
/// Used for both local and network files that need format conversion.
final class RemuxingProxyServer: @unchecked Sendable {
    private var listener: NWListener?
    private var _port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.lunapeek.remux-proxy")
    private let portLock = NSLock()
    private var isRunning = false

    // Active connections
    private var activeConnections: [NWConnection] = []
    private let connectionsLock = NSLock()

    // Data source
    private var fileName: String = ""
    private var fileSize: Int64 = 0
    private var dataReader: ((Int64, Int) async throws -> Data)?
    private var logHandler: ((String) -> Void)?

    // Remuxer
    private var remuxer: FFmpegRemuxer?
    private var remuxedData = Data()
    private let remuxLock = NSLock()
    private var remuxCompleted = false
    private var remuxError: Error?

    var localURL: URL? {
        portLock.lock()
        defer { portLock.unlock() }
        guard _port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(_port)/remuxed.mp4")
    }

    private func log(_ message: String) {
        debugLog("🔄 \(message)")
    }

    /// Start the proxy server with remuxing.
    /// - Parameters:
    ///   - fileName: Original file name
    ///   - fileSize: Total file size
    ///   - reader: Async function to read data from offset
    ///   - logHandler: Optional callback for log messages
    func start(
        fileName: String,
        fileSize: Int64,
        reader: @escaping (Int64, Int) async throws -> Data,
        logHandler: ((String) -> Void)? = nil
    ) async throws {
        self.fileName = fileName
        self.fileSize = fileSize
        self.dataReader = reader
        self.logHandler = logHandler

        // Start remuxer
        await startRemuxer()

        // Start HTTP server
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: .any)
        let weakListener = listener
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = weakListener?.port?.rawValue {
                    self.portLock.lock()
                    self._port = port
                    self.portLock.unlock()
                    self.log("Server started on port \(port)")
                }
            case .failed(let error):
                self.log("Server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        isRunning = true
        listener?.start(queue: queue)

        // Wait for server to be ready
        while true {
            portLock.lock()
            let currentPort = _port
            portLock.unlock()
            if currentPort > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func stop() {
        isRunning = false

        // Stop remuxer
        remuxer?.stop()
        remuxer = nil

        // Cancel all connections
        connectionsLock.lock()
        let connections = activeConnections
        activeConnections.removeAll()
        connectionsLock.unlock()

        for connection in connections {
            connection.cancel()
        }

        listener?.cancel()
        listener = nil
        portLock.lock()
        _port = 0
        portLock.unlock()
        dataReader = nil
    }

    private func startRemuxer() async {
        guard let reader = dataReader else { return }

        remuxer = FFmpegRemuxer()

        // Create delegate to collect remuxed data
        let delegate = RemuxingDelegate { [weak self] data in
            self?.appendRemuxedData(data)
        } onComplete: { [weak self] error in
            self?.remuxLock.lock()
            self?.remuxCompleted = true
            self?.remuxError = error
            self?.remuxLock.unlock()
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
            delegate: delegate
        )
    }

    private func appendRemuxedData(_ data: Data) {
        remuxLock.lock()
        remuxedData.append(data)
        remuxLock.unlock()
    }

    private func getRemuxedData(at offset: Int64, length: Int) -> Data {
        remuxLock.lock()
        let totalSize = remuxedData.count
        guard offset < totalSize else {
            remuxLock.unlock()
            return Data()
        }
        let start = Int(offset)
        let end = min(start + length, totalSize)
        let data = remuxedData.subdata(in: start..<end)
        remuxLock.unlock()
        return data
    }

    private func getRemuxedSize() -> Int64 {
        remuxLock.lock()
        let size = Int64(remuxedData.count)
        remuxLock.unlock()
        return size
    }

    private func isRemuxComplete() -> Bool {
        remuxLock.lock()
        let complete = remuxCompleted
        remuxLock.unlock()
        return complete
    }

    private func restartRemuxer(atOffset offset: Int64) async {
        // Stop current remuxer
        remuxer?.stop()

        // Clear buffer
        remuxLock.lock()
        remuxedData = Data()
        remuxCompleted = false
        remuxError = nil
        remuxLock.unlock()

        // Restart remuxer
        await startRemuxer()

        // Wait for some data
        var attempts = 0
        while getRemuxedSize() < 65536 && !isRemuxComplete() && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        guard isRunning else {
            connection.cancel()
            return
        }

        connectionsLock.lock()
        activeConnections.append(connection)
        connectionsLock.unlock()

        connection.start(queue: queue)
        readNextRequest(connection: connection)
    }

    private func readNextRequest(connection: NWConnection) {
        var buffer = Data()

        func receiveLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
                guard let self else {
                    connection.cancel()
                    return
                }

                if let data = data, !data.isEmpty {
                    buffer.append(data)

                    if let requestString = String(data: buffer, encoding: .utf8),
                       requestString.contains("\r\n\r\n") {
                        self.handleRequest(requestString, connection: connection) {
                            self.readNextRequest(connection: connection)
                        }
                        return
                    }

                    receiveLoop()
                }

                if isComplete || error != nil {
                    connection.cancel()
                }
            }
        }

        receiveLoop()
    }

    private func handleRequest(_ request: String, connection: NWConnection, completion: @escaping () -> Void) {
        guard isRunning else {
            connection.cancel()
            return
        }

        log("Request: \(request.prefix(200))")

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

        Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }

            // For seek requests (large range jumps), we may need to restart remuxing
            if isRangeRequest && rangeStart > self.getRemuxedSize() + 1048576 {
                // Seek request beyond current buffer - restart remuxing from new position
                self.log("Seek request to \(rangeStart), restarting remux")
                await self.restartRemuxer(atOffset: rangeStart)
            }

            // Wait for data to be available at requested position
            var attempts = 0
            while self.getRemuxedSize() < rangeStart + 65536 && !self.isRemuxComplete() && attempts < 100 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                attempts += 1
            }

            let currentSize = self.getRemuxedSize()

            if method == "HEAD" {
                let headers = self.buildHeaders(
                    statusCode: 200,
                    contentLength: currentSize,
                    acceptRanges: "bytes",
                    contentType: "video/mp4"
                )
                self.sendResponse(connection: connection, headers: headers)
                completion()
                return
            }

            // Calculate actual range end
            let actualEndOffset = min(rangeEnd, currentSize - 1)
            let contentLength = max(0, actualEndOffset - rangeStart + 1)

            guard contentLength > 0 else {
                // No data yet, wait and retry
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.sendError(connection: connection, code: 503, message: "Service Unavailable")
                completion()
                return
            }

            let data = self.getRemuxedData(at: rangeStart, length: Int(contentLength))

            let headers: String
            if isRangeRequest {
                headers = self.buildHeaders(
                    statusCode: 206,
                    contentLength: contentLength,
                    acceptRanges: "bytes",
                    contentType: "video/mp4",
                    contentRange: "bytes \(rangeStart)-\(endOffset)/\(currentSize)"
                )
            } else {
                headers = self.buildHeaders(
                    statusCode: 200,
                    contentLength: contentLength,
                    acceptRanges: "bytes",
                    contentType: "video/mp4"
                )
            }

            self.log("Response: \(contentLength) bytes")
            self.sendResponse(connection: connection, headers: headers, body: data)
            completion()
        }
    }

    private func parseRangeHeader(_ value: String) -> (start: Int64, end: Int64)? {
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

    private func buildHeaders(
        statusCode: Int,
        contentLength: Int64,
        acceptRanges: String,
        contentType: String,
        contentRange: String? = nil
    ) -> String {
        var headers = "HTTP/1.1 \(statusCode) \(statusMessage(for: statusCode))\r\n"
        headers += "Content-Length: \(contentLength)\r\n"
        headers += "Accept-Ranges: \(acceptRanges)\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        if let contentRange = contentRange {
            headers += "Content-Range: \(contentRange)\r\n"
        }
        headers += "Cache-Control: no-cache\r\n"
        headers += "\r\n"
        return headers
    }

    private func statusMessage(for code: Int) -> String {
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

    private func sendResponse(connection: NWConnection, headers: String, body: Data? = nil) {
        var data = Data(headers.utf8)
        if let body = body {
            data.append(body)
        }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func sendError(connection: NWConnection, code: Int, message: String) {
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
