// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import Citadel
import NIO

public final class SFTPClientWrapper: SFTPClientProtocol {
    private var sshClient: SSHClient?
    private var _isConnected = false

    public var isConnected: Bool {
        return _isConnected
    }

    public init() {}

    public func connect(configuration: SFTPConfiguration) async throws {
        do {
            let authMethod: SSHAuthenticationMethod
            if let password = configuration.password {
                authMethod = .passwordBased(username: configuration.username, password: password)
            } else {
                throw SFTPError.authenticationFailed
            }

            let client = try await SSHClient.connect(
                host: configuration.host,
                port: configuration.port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
            self.sshClient = client
            _isConnected = true
        } catch {
            throw SFTPError.connectionFailed(error)
        }
    }

    public func disconnect() async {
        if let client = sshClient {
            try? await client.close()
        }
        sshClient = nil
        _isConnected = false
    }

    public func listDirectory(path: String) async throws -> [SFTPFile] {
        guard let sshClient = sshClient else {
            throw SFTPError.notConnected
        }

        do {
            let names = try await sshClient.withSFTP { sftp in
                try await sftp.listDirectory(atPath: path)
            }
            // listDirectory returns [SFTPMessage.Name], each Name contains components
            // We need to flatten the components
            var files: [SFTPFile] = []
            for name in names {
                for component in name.components {
                    // Check if directory using S_IFDIR (0o40000) in permissions
                    let isDirectory = (component.attributes.permissions ?? 0) & 0o170000 == 0o040000
                    let file = SFTPFile(
                        name: component.filename,
                        path: path.isEmpty || path == "/" ? "/\(component.filename)" : "\(path)/\(component.filename)",
                        isDirectory: isDirectory,
                        size: Int64(component.attributes.size ?? 0),
                        modificationDate: component.attributes.accessModificationTime?.modificationTime,
                        permissions: Int(component.attributes.permissions ?? 0)
                    )
                    files.append(file)
                }
            }
            return files
        } catch {
            throw SFTPError.fileNotFound
        }
    }

    public func downloadFile(
        remotePath: String,
        localURL: URL,
        progress: @escaping (SFTPProgress) -> Void
    ) async throws {
        guard let sshClient = sshClient else {
            throw SFTPError.notConnected
        }

        do {
            var buffer = try await sshClient.withSFTP { sftp in
                try await sftp.withFile(filePath: remotePath, flags: .read) { file in
                    try await file.readAll()
                }
            }
            // Convert ByteBuffer to Data
            var data = Data()
            data.append(contentsOf: buffer.readableBytesView)
            try data.write(to: localURL)
            progress(SFTPProgress(bytesTransferred: Int64(data.count), totalBytes: Int64(data.count)))
        } catch {
            throw SFTPError.downloadFailed(error)
        }
    }

    public func cancelDownload() async {
        // Citadel doesn't support direct cancellation
    }
}
