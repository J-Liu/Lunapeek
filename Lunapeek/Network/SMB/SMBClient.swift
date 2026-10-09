// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

/// SMB connection configuration.
public struct SMBConfiguration {
    public let host: String
    public let port: Int
    public let share: String
    public let username: String
    public let password: String
    public let domain: String?

    public init(
        host: String,
        port: Int = 445,
        share: String,
        username: String,
        password: String,
        domain: String? = nil
    ) {
        self.host = host
        self.port = port
        self.share = share
        self.username = username
        self.password = password
        self.domain = domain
    }
}

/// SMB file entry.
public struct SMBFile {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date?

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64,
        modificationDate: Date? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// SMB share info.
public struct SMBShare {
    public let name: String
    public let comment: String

    public init(name: String, comment: String) {
        self.name = name
        self.comment = comment
    }
}

/// SMB download progress.
public struct SMBProgress {
    public let bytesTransferred: Int64
    public let totalBytes: Int64

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }

    public init(bytesTransferred: Int64, totalBytes: Int64) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
    }
}

/// SMB client protocol.
public protocol SMBClientProtocol {
    func login(host: String, port: Int, username: String, password: String, domain: String?) async throws
    func listShares() async throws -> [SMBShare]
    func connectShare(_ share: String) async throws
    func connect(configuration: SMBConfiguration) async throws
    func disconnect() async
    func listDirectory(path: String) async throws -> [SMBFile]
    func deleteFile(path: String, isDirectory: Bool) async throws
    func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SMBProgress) -> Void
    ) async throws
    func readFile(remotePath: String, offset: Int64, length: Int) async throws -> Data
    func getFileSize(remotePath: String) async throws -> Int64
    func cancelDownload() async
    var isConnected: Bool { get }
}

/// SMB client error.
public enum SMBError: Error, LocalizedError {
    case connectionFailed(Error?)
    case authenticationFailed
    case shareNotFound
    case fileNotFound
    case downloadFailed(Error?)
    case notConnected
    case cancelled
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "Connection failed: \(error?.localizedDescription ?? "Unknown error")"
        case .authenticationFailed:
            return "Authentication failed"
        case .shareNotFound:
            return "Share not found"
        case .fileNotFound:
            return "File not found"
        case .downloadFailed(let error):
            return "Download failed: \(error?.localizedDescription ?? "Unknown error")"
        case .notConnected:
            return "Not connected"
        case .cancelled:
            return "Operation cancelled"
        case .unsupportedVersion:
            return "Unsupported SMB version"
        }
    }
}
