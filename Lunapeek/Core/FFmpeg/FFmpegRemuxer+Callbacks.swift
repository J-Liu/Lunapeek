// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation

// C callbacks exposed to FFmpegIOBridge.c

@_cdecl("swiftReadCallback")
public func swiftReadCallback(_ swiftContext: UnsafeMutableRawPointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ size: Int32) -> Int32 {
    guard let context = swiftContext else { return -1 }
    let remuxer = Unmanaged<FFmpegRemuxer>.fromOpaque(context).takeUnretainedValue()
    guard let buffer = buf else { return -1 }
    return Int32(remuxer.handleRead(buf: buffer, size: Int(size)))
}

@_cdecl("swiftWriteCallback")
public func swiftWriteCallback(_ swiftContext: UnsafeMutableRawPointer?, _ buf: UnsafePointer<UInt8>?, _ size: Int32) -> Int32 {
    guard let context = swiftContext else { return -1 }
    let remuxer = Unmanaged<FFmpegRemuxer>.fromOpaque(context).takeUnretainedValue()
    guard let buffer = buf else { return -1 }
    return Int32(remuxer.handleWrite(buf: buffer, size: Int(size)))
}

@_cdecl("swiftSeekCallback")
public func swiftSeekCallback(_ swiftContext: UnsafeMutableRawPointer?, _ offset: Int64, _ whence: Int32) -> Int64 {
    guard let context = swiftContext else { return -1 }
    let remuxer = Unmanaged<FFmpegRemuxer>.fromOpaque(context).takeUnretainedValue()
    return remuxer.handleSeek(offset: offset, whence: Int(whence))
}
