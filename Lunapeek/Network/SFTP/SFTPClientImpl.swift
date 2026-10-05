// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation

/// Placeholder SFTP client implementation.
/// Actual implementation requires libssh or similar library.
public final class SFTPClient: SFTPClientProtocol {
    private var configuration: SFTPConfiguration?
    private var _isConnected = false

    public var isConnected: Bool {
        return _isConnected
    }

    public init() {}

    public func connect(configuration: SFTPConfiguration) async throws {
        self.configuration = configuration

        // TODO: Implement with libssh or mft library
        // For now, simulate connection
        _isConnected = true
    }

    public func disconnect() async {
        _isConnected = false
        configuration = nil
    }

    public func listDirectory(path: String) async throws -> [SFTPFile] {
        guard _isConnected else {
            throw SFTPError.notConnected
        }

        // TODO: Implement with libssh sftp_ls
        return []
    }

    public func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SFTPProgress) -> Void
    ) async throws {
        guard _isConnected else {
            throw SFTPError.notConnected
        }

        // TODO: Implement with libssh sftp_read
    }

    public func cancelDownload() async {
        // TODO: Implement download cancellation
    }
}