// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation

/// Placeholder SMB client implementation.
/// Actual implementation requires libsmb2 (LGPL v2.1, must be dynamically linked).
public final class SMBClient: SMBClientProtocol {
    private var configuration: SMBConfiguration?
    private var _isConnected = false

    public var isConnected: Bool {
        return _isConnected
    }

    public init() {}

    public func connect(configuration: SMBConfiguration) async throws {
        self.configuration = configuration

        // TODO: Implement with libsmb2
        // Note: libsmb2 is LGPL v2.1, must be dynamically linked for App Store compliance
        _isConnected = true
    }

    public func disconnect() async {
        _isConnected = false
        configuration = nil
    }

    public func listDirectory(path: String) async throws -> [SMBFile] {
        guard _isConnected else {
            throw SMBError.notConnected
        }

        // TODO: Implement with libsmb2 smb2_opendir / smb2_readdir
        return []
    }

    public func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SMBProgress) -> Void
    ) async throws {
        guard _isConnected else {
            throw SMBError.notConnected
        }

        // TODO: Implement with libsmb2 smb2_open / smb2_read
    }

    public func cancelDownload() async {
        // TODO: Implement download cancellation
    }
}