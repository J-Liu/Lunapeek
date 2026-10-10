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
            let showHidden = Settings.shared.showHiddenFiles

            for name in names {
                for component in name.components {
                    // Filter hidden files if setting is disabled
                    if !showHidden && component.filename.hasPrefix(".") {
                        continue
                    }
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
            // Get file size first via listDirectory
            let parentPath = (remotePath as NSString).deletingLastPathComponent
            let fileName = (remotePath as NSString).lastPathComponent
            let files = try await sshClient.withSFTP { sftp in
                try await sftp.listDirectory(atPath: parentPath.isEmpty ? "/" : parentPath)
            }

            var totalBytes: Int64 = 0
            for name in files {
                for component in name.components {
                    if component.filename == fileName {
                        totalBytes = Int64(component.attributes.size ?? 0)
                        break
                    }
                }
                if totalBytes > 0 { break }
            }

            // Open file and read in chunks
            let fileHandle = try await sshClient.withSFTP { sftp in
                try await sftp.openFile(filePath: remotePath, flags: .read)
            }

            defer {
                Task {
                    try? await fileHandle.close()
                }
            }

            let chunkSize = 65536 // 64KB chunks
            var bytesTransferred: Int64 = 0
            var outputData = Data()

            while true {
                let buffer = try await fileHandle.read(from: UInt64(bytesTransferred), length: UInt32(chunkSize))
                if buffer.readableBytes == 0 { break }

                let bytes = Data(buffer.readableBytesView)
                outputData.append(bytes)
                bytesTransferred += Int64(buffer.readableBytes)

                let prog = SFTPProgress(bytesTransferred: bytesTransferred, totalBytes: totalBytes)
                progress(prog)
            }

            try outputData.write(to: localURL)
        } catch {
            throw SFTPError.downloadFailed(error)
        }
    }

    public func cancelDownload() async {
        // Citadel doesn't support direct cancellation
    }

    public func deleteFile(path: String, isDirectory: Bool = false) async throws {
        guard let sshClient = sshClient else {
            throw SFTPError.notConnected
        }

        do {
            try await sshClient.withSFTP { sftp in
                if isDirectory {
                    try await sftp.rmdir(at: path)
                } else {
                    try await sftp.remove(at: path)
                }
            }
        } catch {
            throw SFTPError.fileNotFound
        }
    }

    public func getHomeDirectory() async throws -> String {
        guard let sshClient = sshClient else {
            throw SFTPError.notConnected
        }

        return try await sshClient.withSFTP { sftp in
            try await sftp.getRealPath(atPath: ".")
        }
    }

    public func readFile(remotePath: String, offset: Int64, length: Int) async throws -> Data {
        guard let sshClient = sshClient else {
            throw SFTPError.notConnected
        }

        return try await sshClient.withSFTP { sftp in
            try await sftp.withFile(filePath: remotePath, flags: .read) { file in
                let buffer = try await file.read(from: UInt64(offset), length: UInt32(length))
                var data = Data()
                data.append(contentsOf: buffer.readableBytesView)
                return data
            }
        }
    }

    public func getFileSize(remotePath: String) async throws -> Int64 {
        guard let sshClient = sshClient else {
            throw SFTPError.notConnected
        }

        return try await sshClient.withSFTP { sftp in
            let attrs = try await sftp.getAttributes(at: remotePath)
            return Int64(attrs.size ?? 0)
        }
    }
}
