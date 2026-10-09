// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import Network

/// HTTP proxy server for streaming remote files to AVPlayer.
final class HTTPProxyServer: @unchecked Sendable {
    private var listener: NWListener?
    private var _port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.lunapeek.http-proxy")
    private let portLock = NSLock()

    // Data source
    private var fileSize: Int64 = 0
    private var fileName: String = ""
    private var dataReader: ((Int64, Int) async throws -> Data)?
    private var logHandler: ((String) -> Void)?

    var localURL: URL? {
        portLock.lock()
        defer { portLock.unlock() }
        guard _port > 0 else { return nil }
        // Include filename in URL for proper demuxer selection
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video"
        return URL(string: "http://127.0.0.1:\(_port)/\(encodedName)")
    }

    private var contentType: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "mkv":
            return "video/x-matroska"
        case "avi":
            return "video/x-msvideo"
        case "webm":
            return "video/webm"
        case "ts", "mts", "m2ts":
            return "video/mp2t"
        case "flv":
            return "video/x-flv"
        default:
            return "application/octet-stream"
        }
    }

    private func log(_ message: String) {
        debugLog("🌐 \(message)")
    }

    /// Start the proxy server with a data reader.
    /// - Parameters:
    ///   - fileName: File name for Content-Type detection
    ///   - fileSize: Total size of the file
    ///   - reader: Async function to read data from offset with specified length
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
        listener?.cancel()
        listener = nil
        portLock.lock()
        _port = 0
        portLock.unlock()
        dataReader = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Keep reading requests on the same connection (HTTP keep-alive)
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

                    // Check if we have a complete HTTP request (ends with \r\n\r\n)
                    if let requestString = String(data: buffer, encoding: .utf8),
                       requestString.contains("\r\n\r\n") {
                        // Process request, then continue reading next request
                        self.handleRequest(requestString, connection: connection) {
                            // After response is sent, wait for next request
                            self.readNextRequest(connection: connection)
                        }
                        return
                    }

                    // Continue receiving
                    receiveLoop()
                }

                if isComplete || error != nil {
                    // Connection closed by client
                    connection.cancel()
                }
            }
        }

        receiveLoop()
    }

    private func handleRequest(_ request: String, connection: NWConnection, completion: @escaping () -> Void) {
        // Debug log
        log("Request: \(request.prefix(200))")

        // Parse request
        let lines = request.split(separator: "\r\n")
        guard let requestLine = lines.first else {
            sendError(connection: connection, code: 400, message: "Bad Request")
            connection.cancel()
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 3 else {
            sendError(connection: connection, code: 400, message: "Bad Request")
            connection.cancel()
            return
        }

        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            sendError(connection: connection, code: 405, message: "Method Not Allowed")
            connection.cancel()
            return
        }

        // Parse Range header
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = fileSize - 1
        var isRangeRequest = false

        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                isRangeRequest = true
                let rangeValue = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if let range = parseRangeHeader(rangeValue) {
                    rangeStart = range.start
                    rangeEnd = min(range.end, fileSize - 1)
                }
            }
        }

        let contentLength = rangeEnd - rangeStart + 1

        Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }

            if method == "HEAD" {
                // HEAD request - just send headers
                let headers = self.buildHeaders(
                    statusCode: isRangeRequest ? 206 : 200,
                    contentLength: self.fileSize,
                    acceptRanges: "bytes",
                    contentType: self.contentType
                )
                self.sendResponse(connection: connection, headers: headers)
                completion()
                return
            }

            // GET request
            guard let reader = self.dataReader else {
                self.sendError(connection: connection, code: 500, message: "No Data Source")
                connection.cancel()
                return
            }

            do {
                // Read data from source
                let length = Int(contentLength)
                self.log("Read: \(rangeStart)-\(rangeEnd) (\(length) bytes)")
                let data = try await reader(rangeStart, length)
                self.log("Read \(data.count) bytes OK")

                // Build response headers
                let headers: String
                if isRangeRequest {
                    headers = self.buildHeaders(
                        statusCode: 206,
                        contentLength: contentLength,
                        acceptRanges: "bytes",
                        contentType: self.contentType,
                        contentRange: "bytes \(rangeStart)-\(rangeEnd)/\(self.fileSize)"
                    )
                } else {
                    headers = self.buildHeaders(
                        statusCode: 200,
                        contentLength: self.fileSize,
                        acceptRanges: "bytes",
                        contentType: self.contentType
                    )
                }

                self.log("Response: \(headers)")
                self.sendResponse(connection: connection, headers: headers, body: data)
                completion()
            } catch {
                self.log("Read error: \(error)")
                self.sendError(connection: connection, code: 500, message: "Read Error")
                connection.cancel()
            }
        }
    }

    private func parseRangeHeader(_ value: String) -> (start: Int64, end: Int64)? {
        // Format: bytes=start-end or bytes=start-
        guard value.hasPrefix("bytes=") else { return nil }
        let rangeStr = String(value.dropFirst(6))

        if rangeStr.contains("-") {
            let parts = rangeStr.split(separator: "-")
            if let startStr = parts.first, let start = Int64(startStr) {
                let end: Int64
                if parts.count > 1, let endVal = Int64(parts[1]) {
                    end = endVal
                } else {
                    end = fileSize - 1
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
