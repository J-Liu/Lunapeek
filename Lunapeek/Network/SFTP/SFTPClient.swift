// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation

/// SFTP connection configuration.
public struct SFTPConfiguration {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String?
    public let privateKey: Data?
    public let passphrase: String?

    public init(
        host: String,
        port: Int = 22,
        username: String,
        password: String? = nil,
        privateKey: Data? = nil,
        passphrase: String? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.privateKey = privateKey
        self.passphrase = passphrase
    }
}

/// SFTP file entry.
public struct SFTPFile {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date?
    public let permissions: Int

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64,
        modificationDate: Date? = nil,
        permissions: Int = 0
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
    }
}

/// SFTP download progress.
public struct SFTPProgress {
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let speed: Int64

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }

    public init(bytesTransferred: Int64, totalBytes: Int64, speed: Int64 = 0) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.speed = speed
    }
}

/// SFTP client protocol.
public protocol SFTPClientProtocol {
    func connect(configuration: SFTPConfiguration) async throws
    func disconnect() async
    func listDirectory(path: String) async throws -> [SFTPFile]
    func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SFTPProgress) -> Void
    ) async throws
    func cancelDownload() async
    var isConnected: Bool { get }
}

/// SFTP client error.
public enum SFTPError: Error {
    case connectionFailed(Error?)
    case authenticationFailed
    case fileNotFound
    case downloadFailed(Error?)
    case notConnected
    case cancelled
}