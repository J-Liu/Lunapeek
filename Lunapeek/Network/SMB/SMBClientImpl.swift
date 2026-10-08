// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import SMBClient

public final class SMBClientWrapper: SMBClientProtocol {
    private var client: SMBClient?
    private var share: String?
    private var _isLoggedIn = false
    private var _isConnected = false

    public var isConnected: Bool {
        return _isConnected
    }

    public var isLoggedIn: Bool {
        return _isLoggedIn
    }

    public init() {}

    public func login(host: String, port: Int, username: String, password: String, domain: String?) async throws {
        do {
            let client = SMBClient(host: host, port: port)
            try await client.login(
                username: username,
                password: password,
                domain: domain
            )
            self.client = client
            _isLoggedIn = true
        } catch {
            throw SMBError.authenticationFailed
        }
    }

    public func listShares() async throws -> [SMBShare] {
        guard let client = client, _isLoggedIn else {
            throw SMBError.notConnected
        }

        do {
            let shares = try await client.listShares()
            return shares.map { share in
                SMBShare(name: share.name, comment: share.comment)
            }
        } catch {
            throw SMBError.connectionFailed(error)
        }
    }

    public func connectShare(_ share: String) async throws {
        guard let client = client, _isLoggedIn else {
            throw SMBError.notConnected
        }

        do {
            try await client.connectShare(share)
            self.share = share
            _isConnected = true
        } catch {
            throw SMBError.shareNotFound
        }
    }

    public func connect(configuration: SMBConfiguration) async throws {
        try await login(
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            password: configuration.password,
            domain: configuration.domain
        )
        try await connectShare(configuration.share)
    }

    public func disconnect() async {
        if let client = client {
            if _isConnected {
                _ = try? await client.disconnectShare()
            }
            if _isLoggedIn {
                _ = try? await client.logoff()
            }
        }
        client = nil
        share = nil
        _isLoggedIn = false
        _isConnected = false
    }

    public func listDirectory(path: String) async throws -> [SMBFile] {
        guard let client = client, _isConnected else {
            throw SMBError.notConnected
        }

        do {
            let files = try await client.listDirectory(path: path)
            let showHidden = Settings.shared.showHiddenFiles
            return files.compactMap { file in
                // Filter hidden files if setting is disabled
                if !showHidden && file.name.hasPrefix(".") {
                    return nil
                }
                return SMBFile(
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

    public func deleteFile(path: String, isDirectory: Bool = false) async throws {
        guard let client = client, _isConnected else {
            throw SMBError.notConnected
        }

        do {
            if isDirectory {
                try await client.deleteDirectory(path: path)
            } else {
                try await client.deleteFile(path: path)
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
        guard let client = client, _isConnected else {
            throw SMBError.notConnected
        }

        do {
            try await client.download(path: remotePath, localPath: localURL, overwrite: true) { progressValue in
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
