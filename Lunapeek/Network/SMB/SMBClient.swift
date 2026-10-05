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
    func connect(configuration: SMBConfiguration) async throws
    func disconnect() async
    func listDirectory(path: String) async throws -> [SMBFile]
    func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SMBProgress) -> Void
    ) async throws
    func cancelDownload() async
    var isConnected: Bool { get }
}

/// SMB client error.
public enum SMBError: Error {
    case connectionFailed(Error?)
    case authenticationFailed
    case shareNotFound
    case fileNotFound
    case downloadFailed(Error?)
    case notConnected
    case cancelled
    case unsupportedVersion
}
