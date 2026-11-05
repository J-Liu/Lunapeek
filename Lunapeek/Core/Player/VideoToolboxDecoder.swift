// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import VideoToolbox
import CoreVideo
import FFmpegBridge

/// Hardware video decoder using VideoToolbox (iOS native)
public final class VideoToolboxDecoder: LPVideoDecoderProtocol {
    public var timebase: AVRational = AVRational(num: 1, den: 1)
    public var onFrameDecoded: ((LPVideoFrame) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var lastPts: Int64 = 0

    public init() {}

    public func open(codecParams: UnsafeMutablePointer<AVCodecParameters>, streamIndex: Int) -> Bool {
        // Create format description from codec parameters
        let status = createFormatDescription(from: codecParams)

        guard status == noErr, let formatDescription = formatDescription else {
            debugLog("❌ VideoToolbox: Failed to create format description, status: \(status)")
            return false
        }

        // Create decompression session
        let callback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, OSStatus, VTDecodeInfoFlags, CVImageBuffer?, CMTime, CMTime) -> Void = { sourceFrameRefCon, _, status, _, imageBuffer, pts, duration in
            guard status == noErr, let imageBuffer = imageBuffer else { return }

            let decoder = Unmanaged<VideoToolboxDecoder>.fromOpaque(sourceFrameRefCon!).takeUnretainedValue()
            // Keyframe detection not directly available in callback, set to true
            // Actual keyframe status is tracked at packet level
            let frame = LPVideoFrame(
                pixelBuffer: imageBuffer,
                pts: pts,
                duration: duration,
                isSync: true
            )
            decoder.onFrameDecoded?(frame)
        }

        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: callback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let sessionStatus = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )

        guard sessionStatus == noErr else {
            debugLog("❌ VideoToolbox: Failed to create session, status: \(sessionStatus)")
            return false
        }

        debugLog("✅ VideoToolbox: Decoder opened successfully")
        return true
    }

    public func decode(packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        guard let session = session, let formatDescription = formatDescription else {
            return false
        }

        // Create CMSampleBuffer from AVPacket
        let ptsValue = packet.pointee.pts
        let pts = CMTime(
            value: ptsValue < 0 ? lastPts + 1 : ptsValue,
            timescale: timebase.den,
            flags: .valid,
            epoch: 0
        )
        let duration = CMTime(
            value: packet.pointee.duration,
            timescale: timebase.den,
            flags: .valid,
            epoch: 0
        )

        lastPts = pts.value

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        let status = createSampleBuffer(
            from: packet,
            formatDescription: formatDescription,
            pts: pts,
            duration: duration,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer = sampleBuffer else {
            debugLog("❌ VideoToolbox: Failed to create sample buffer")
            return false
        }

        // Decode
        let decodeFlags: VTDecodeFrameFlags = []
        var infoFlags: VTDecodeInfoFlags = []

        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )

        return decodeStatus == noErr
    }

    public func flush() {
        guard let session = session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    public func close() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        formatDescription = nil
    }

    // MARK: - Private

    private func createFormatDescription(from codecParams: UnsafeMutablePointer<AVCodecParameters>) -> OSStatus {
        let codecId = codecParams.pointee.codec_id

        var status: OSStatus

        if codecId == AV_CODEC_ID_H264 {
            // H.264
            guard let extradata = codecParams.pointee.extradata,
                  extradata.pointee != 0,
                  codecParams.pointee.extradata_size > 0 else {
                return -1
            }

            let data = Data(bytes: extradata, count: Int(codecParams.pointee.extradata_size))
            status = createH264FormatDescription(from: data)

        } else if codecId == AV_CODEC_ID_HEVC {
            // H.265/HEVC
            guard let extradata = codecParams.pointee.extradata,
                  extradata.pointee != 0,
                  codecParams.pointee.extradata_size > 0 else {
                return -1
            }

            let data = Data(bytes: extradata, count: Int(codecParams.pointee.extradata_size))
            status = createHEVCFormatDescription(from: data)

        } else {
            debugLog("❌ VideoToolbox: Unsupported codec \(codecId)")
            return -1
        }

        return status
    }

    private func createH264FormatDescription(from avcC: Data) -> OSStatus {
        // Parse avcC atom to extract SPS/PPS NAL units
        // Format: length (1) + SPS count + SPS length + SPS data + PPS count + PPS length + PPS data
        guard avcC.count > 7 else { return -1 }

        var formatDescription: CMVideoFormatDescription?

        // Simple case: treat entire extradata as single parameter set (avcC format)
        // In reality, you'd parse NAL units properly from avcC atom
        avcC.withUnsafeBytes { bytes in
            guard let baseAddr = bytes.baseAddress else { return }

            // Create array of pointers and sizes for parameter sets
            var pointers: [UnsafePointer<UInt8>] = [baseAddr.assumingMemoryBound(to: UInt8.self)]
            var sizes: [Int] = [avcC.count]

            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: 1,
                parameterSetPointers: &pointers,
                parameterSetSizes: &sizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &formatDescription
            )
            if status == noErr {
                self.formatDescription = formatDescription
            }
        }

        return formatDescription != nil ? noErr : -1
    }

    private func createHEVCFormatDescription(from hvcC: Data) -> OSStatus {
        guard hvcC.count > 7 else { return -1 }

        var formatDescription: CMVideoFormatDescription?

        hvcC.withUnsafeBytes { bytes in
            guard let baseAddr = bytes.baseAddress else { return }

            var pointers: [UnsafePointer<UInt8>] = [baseAddr.assumingMemoryBound(to: UInt8.self)]
            var sizes: [Int] = [hvcC.count]

            let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: 1,
                parameterSetPointers: &pointers,
                parameterSetSizes: &sizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
            if status == noErr {
                self.formatDescription = formatDescription
            }
        }

        return formatDescription != nil ? noErr : -1
    }

    private func createSampleBuffer(
        from packet: UnsafeMutablePointer<AVPacket>,
        formatDescription: CMVideoFormatDescription,
        pts: CMTime,
        duration: CMTime,
        sampleBufferOut: UnsafeMutablePointer<CMSampleBuffer?>
    ) -> OSStatus {
        var sampleBuffer: CMSampleBuffer?

        let blockBuffer = createBlockBuffer(from: packet)
        guard let blockBuffer = blockBuffer else {
            return -1
        }

        let status = CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)],
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        if status == noErr {
            sampleBufferOut.pointee = sampleBuffer
        }

        return status
    }

    private func createBlockBuffer(from packet: UnsafeMutablePointer<AVPacket>) -> CMBlockBuffer? {
        guard let data = packet.pointee.data else { return nil }

        var blockBuffer: CMBlockBuffer?
        let size = Int(packet.pointee.size)

        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: data,
            blockLength: size,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: size,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        return status == noErr ? blockBuffer : nil
    }
}
