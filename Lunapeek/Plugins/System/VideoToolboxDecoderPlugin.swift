// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import CoreVideo
import VideoToolbox
import Foundation

/// Video decoder using VideoToolbox for hardware-accelerated H.264/HEVC decoding.
public final class VideoToolboxDecoderPlugin: VideoDecoderPlugin {
    private var session: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    private var decodedFrames: [VideoFrame] = []
    private var isConfigured = false

    public init() {}

    public func configure(with formatDescription: MediaFormatDescription) async throws {
        reset()

        guard formatDescription.videoProperties != nil else {
            throw VideoDecoderError.unsupportedFormat
        }

        let videoProps = formatDescription.videoProperties!

        var formatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: formatDescription.codecId,
            dimensions: CGSize(width: CGFloat(videoProps.width), height: CGFloat(videoProps.height)),
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        guard status == noErr, let formatDesc = formatDesc else {
            throw VideoDecoderError.configurationFailed(nil)
        }

        self.formatDescription = formatDesc

        let decoderConfig: [String: Any] = [
            kVTDecompressionDecoderOption_RequiredDecoderGPURegistryID as String: false,
            kVTDecompressionPropertyKey_RealTime as String: true
        ]

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { unownedClient, status, flags, imageBuffer, pts, duration in
                let decoder = Unmanaged<VideoToolboxDecoderPlugin>.fromOpaque(unownedClient).takeUnretainedValue()
                decoder.handleDecodedFrame(
                    status: status,
                    imageBuffer: imageBuffer,
                    pts: pts,
                    duration: duration
                )
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: decoderConfig as CFDictionary,
            imageBufferAttributes: nil,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )

        guard sessionStatus == noErr, let session = session else {
            throw VideoDecoderError.configurationFailed(nil)
        }

        self.session = session
        isConfigured = true
    }

    private func handleDecodedFrame(status: OSStatus, imageBuffer: CVImageBuffer?, pts: CMTime, duration: CMTime) {
        guard status == noErr, let imageBuffer = imageBuffer else { return }

        let pixelBuffer = CVPixelBuffer.from(imageBuffer)
        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTimestamp: CMTimeGetSeconds(pts).times(1_000_000),
            duration: CMTimeGetSeconds(duration).times(1_000_000)
        )
        decodedFrames.append(frame)
    }

    public func decode(packet: MediaPacket) async throws -> [VideoFrame] {
        guard isConfigured, let session = session else {
            throw VideoDecoderError.notConfigured
        }

        decodedFrames.removeAll()

        var sampleBuffer: CMSampleBuffer?
        let pts = CMTime(
            seconds: Double(packet.presentationTimestamp) / 1_000_000,
            preferredTimescale: 1_000_000
        )
        let duration = CMTime(
            seconds: Double(packet.duration) / 1_000_000,
            preferredTimescale: 1_000_000
        )

        var timingInfo = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBufferStatus = noErr
        packet.data.withUnsafeBytes { bytes in
            var blockBuffer: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: packet.data.count,
                providedBlockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: packet.data.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            if let blockBuffer = blockBuffer {
                CMBlockBufferReplaceDataBytes(
                    with: bytes.baseAddress!,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: packet.data.count
                )

                CMSampleBufferCreate(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: blockBuffer,
                    dataReady: true,
                    makeDataReadyCallback: nil,
                    refcon: nil,
                    formatDescription: formatDescription,
                    sampleCount: 1,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timingInfo,
                    sampleSizeEntryCount: 0,
                    sampleSizeArray: nil,
                    sampleBufferOut: &sampleBuffer
                )
            }
        }

        guard let sampleBuffer = sampleBuffer else {
            throw VideoDecoderError.decodingFailed(nil)
        }

        let decodeFlags: VTDecodeFrameFlags = [
            ._EnableAsynchronousDecompression,
            ._EnableTemporalProcessing
        ]

        var infoFlags: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeSampleBuffer(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            infoFlagsOut: &infoFlags
        )

        guard decodeStatus == noErr else {
            throw VideoDecoderError.decodingFailed(nil)
        }

        return decodedFrames
    }

    public func flush() async throws -> [VideoFrame] {
        guard let session = session else {
            return []
        }

        VTDecompressionSessionWaitForAsynchronousFrames(session)
        let frames = decodedFrames
        decodedFrames.removeAll()
        return frames
    }

    public func reset() async {
        if let session = session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        decodedFrames.removeAll()
        isConfigured = false
    }

    public static func supports(codec: String) -> Bool {
        let supportedCodecs = ["h264", "avc1", "hvc1", "hev1", "hevc"]
        return supportedCodecs.contains(codec.lowercased())
    }
}

private extension Double {
    func times(_ multiplier: Int64) -> Int64 {
        Int64(self * Double(multiplier))
    }
}

private extension CVPixelBuffer {
    static func from(_ imageBuffer: CVImageBuffer) -> CVPixelBuffer {
        CVPixelBuffer.from(imageBuffer as! CVPixelBuffer)
    }
}