// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import SMBClient

public final class SMBClientWrapper: SMBClientProtocol {
    private var client: SMBClient?
    private var share: String?
    private var _isConnected = false

    public var isConnected: Bool {
        return _isConnected
    }

    public init() {}

    public func connect(configuration: SMBConfiguration) async throws {
        do {
            let client = SMBClient(host: configuration.host, port: configuration.port)
            try await client.login(
                username: configuration.username,
                password: configuration.password,
                domain: configuration.domain
            )
            try await client.connectShare(configuration.share)
            self.client = client
            self.share = configuration.share
            _isConnected = true
        } catch {
            throw SMBError.connectionFailed(error)
        }
    }

    public func disconnect() async {
        if let client = client {
            try? await client.disconnectShare()
            try? await client.logoff()
        }
        client = nil
        share = nil
        _isConnected = false
    }

    public func listDirectory(path: String) async throws -> [SMBFile] {
        guard let client = client else {
            throw SMBError.notConnected
        }

        do {
            let files = try await client.listDirectory(path: path)
            return files.map { file in
                SMBFile(
                    name: file.name,
                    path: path.isEmpty || path == "/" ? "/\(file.name)" : "\(path)/\(file.name)",
                    isDirectory: file.isDirectory,
                    size: Int64(file.size),
                    modificationDate: file.lastWriteTime
                )
            }
        } catch {
            throw SMBError.fileNotFound
        }
    }

    public func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SMBProgress) -> Void
    ) async throws {
        guard let client = client else {
            throw SMBError.notConnected
        }

        do {
            try await client.download(path: remotePath, localPath: localURL, overwrite: true) { progressValue in
                // SMBClient provides progress as Double (0.0 - 1.0)
                // We need to get file size for actual bytes
                progress(SMBProgress(bytesTransferred: 0, totalBytes: 0))
            }
        } catch {
            throw SMBError.downloadFailed(error)
        }
    }

    public func cancelDownload() async {
        // SMBClient library doesn't support cancellation directly
    }
}
