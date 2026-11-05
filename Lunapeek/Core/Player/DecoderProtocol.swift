// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import FFmpegBridge

/// Decoder protocol for both video and audio
public protocol LPDecoderProtocol: AnyObject {
    var timebase: AVRational { get set }

    /// Initialize decoder with codec parameters
    func open(codecParams: UnsafeMutablePointer<AVCodecParameters>, streamIndex: Int) -> Bool

    /// Decode a packet
    func decode(packet: UnsafeMutablePointer<AVPacket>) -> Bool

    /// Flush decoder (drain remaining frames)
    func flush()

    /// Close decoder and release resources
    func close()
}

/// Video decoder protocol
public protocol LPVideoDecoderProtocol: LPDecoderProtocol {
    var onFrameDecoded: ((LPVideoFrame) -> Void)? { get set }
}

/// Audio decoder protocol
public protocol LPAudioDecoderProtocol: LPDecoderProtocol {
    var onAudioDecoded: ((LPAudioFrame) -> Void)? { get set }
}
