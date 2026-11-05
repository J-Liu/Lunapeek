// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import AudioToolbox
import CoreAudio
import CoreMedia
import FFmpegBridge

/// Hardware audio decoder using AudioToolbox (iOS Core Audio)
public final class AudioToolboxDecoder: LPAudioDecoderProtocol {
    public var timebase: AVRational = AVRational(num: 1, den: 1)
    public var onAudioDecoded: ((LPAudioFrame) -> Void)?

    private var audioConverter: AudioConverterRef?
    private var inputFormat: AudioStreamBasicDescription?
    private var outputFormat: AudioStreamBasicDescription?
    private var pendingPackets: [Data] = []
    private let packetLock = NSLock()
    private var outputChannels: Int32 = 0
    private var outputSampleRate: Int32 = 0

    public init() {}

    public func open(codecParams: UnsafeMutablePointer<AVCodecParameters>, streamIndex: Int) -> Bool {
        let codecId = codecParams.pointee.codec_id
        let sampleRate = codecParams.pointee.sample_rate
        let channels = codecParams.pointee.ch_layout.nb_channels

        // Determine AudioFormatID from FFmpeg codec
        let audioFormatID: AudioFormatID
        switch codecId {
        case AV_CODEC_ID_AAC:
            audioFormatID = kAudioFormatMPEG4AAC
        case AV_CODEC_ID_AAC_LATM:
            audioFormatID = kAudioFormatMPEG4AAC
        case AV_CODEC_ID_AC3:
            audioFormatID = kAudioFormatAC3
        case AV_CODEC_ID_EAC3:
            audioFormatID = kAudioFormatEnhancedAC3
        case AV_CODEC_ID_ALAC:
            audioFormatID = kAudioFormatAppleLossless
        case AV_CODEC_ID_PCM_S16LE, AV_CODEC_ID_PCM_S16BE:
            audioFormatID = kAudioFormatLinearPCM
        default:
            debugLog("❌ AudioToolbox: Unsupported codec \(codecId)")
            return false
        }

        // Create input format description
        var inputDesc = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: audioFormatID,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )

        // Set format-specific flags
        if codecId == AV_CODEC_ID_PCM_S16LE {
            inputDesc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
            inputDesc.mBitsPerChannel = 16
            inputDesc.mBytesPerPacket = 2 * UInt32(channels)
            inputDesc.mFramesPerPacket = 1
            inputDesc.mBytesPerFrame = inputDesc.mBytesPerPacket
        }

        // Create output format (PCM)
        var outputDesc = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2 * UInt32(channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * UInt32(channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        // Create audio converter
        let status = AudioConverterNew(&inputDesc, &outputDesc, &audioConverter)

        guard status == noErr, audioConverter != nil else {
            debugLog("❌ AudioToolbox: Failed to create AudioConverter, status: \(status)")
            return false
        }

        self.inputFormat = inputDesc
        self.outputFormat = outputDesc
        self.outputChannels = Int32(channels)
        self.outputSampleRate = sampleRate

        debugLog("✅ AudioToolbox: Decoder opened for codec \(codecId), sampleRate: \(sampleRate), channels: \(channels)")
        return true
    }

    public func decode(packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        guard audioConverter != nil else { return false }

        // Get packet data
        let dataSize = Int(packet.pointee.size)
        guard let dataPtr = packet.pointee.data else { return false }
        let inputData = Data(bytes: dataPtr, count: dataSize)

        // Store input packet for callback
        packetLock.lock()
        pendingPackets.append(inputData)
        packetLock.unlock()

        // Calculate output buffer size
        let outputFrameCount: UInt32 = 4096
        let outputSize = Int(outputFrameCount) * Int(outputFormat!.mBytesPerFrame)
        var outputBuffer = [UInt8](repeating: 0, count: outputSize)

        // Prepare output buffer using withUnsafeMutableBytes for correct pointer handling
        let result = outputBuffer.withUnsafeMutableBytes { bufferPtr in
            guard let baseAddr = bufferPtr.baseAddress else { return false }

            var outputData = AudioBufferList()
            outputData.mNumberBuffers = 1
            outputData.mBuffers.mNumberChannels = outputFormat!.mChannelsPerFrame
            outputData.mBuffers.mDataByteSize = UInt32(outputSize)
            outputData.mBuffers.mData = baseAddr

            var ioOutputData = outputData
            var ioOutputFrameCount = outputFrameCount

            // Convert
            let status = AudioConverterFillComplexBuffer(
                audioConverter!,
                inputCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                &ioOutputFrameCount,
                &ioOutputData,
                nil
            )

            guard status == noErr else {
                debugLog("⚠️ AudioToolbox: Conversion returned status: \(status)")
                return false
            }

            // Create audio frame with decoded PCM data
            let decodedSize = Int(ioOutputData.mBuffers.mDataByteSize)
            if let mData = ioOutputData.mBuffers.mData {
                let decodedData = Data(bytes: mData, count: decodedSize)

                // Convert PTS to CMTime using timebase
                let ptsSec = Double(packet.pointee.pts) * Double(timebase.num) / Double(timebase.den)
                let durationSec = Double(packet.pointee.duration) * Double(timebase.num) / Double(timebase.den)
                let pts = CMTime(seconds: ptsSec, preferredTimescale: 1000000000)
                let duration = CMTime(seconds: durationSec, preferredTimescale: 1000000000)

                let frame = LPAudioFrame(
                    data: decodedData,
                    pts: pts,
                    duration: duration,
                    sampleRate: outputSampleRate,
                    channels: outputChannels,
                    format: AV_SAMPLE_FMT_S16  // Output is signed 16-bit PCM
                )

                onAudioDecoded?(frame)
                return true
            }

            return false
        }

        return result
    }

    public func flush() {
        // No buffering needed for AudioToolbox
    }

    public func close() {
        if let converter = audioConverter {
            AudioConverterDispose(converter)
            audioConverter = nil
        }
        inputFormat = nil
        outputFormat = nil
    }

    // MARK: - Input Callback

    private let inputCallback: AudioConverterComplexInputDataProc = { converter, ioNumberPackets, ioData, ioPacketDescription, inUserData in
        guard let userData = inUserData else { return noErr }

        let decoder = Unmanaged<AudioToolboxDecoder>.fromOpaque(userData).takeUnretainedValue()

        decoder.packetLock.lock()
        defer { decoder.packetLock.unlock() }

        guard !decoder.pendingPackets.isEmpty else {
            ioNumberPackets.pointee = UInt32(0)
            return -1  // Return error when no data available
        }

        let packetData = decoder.pendingPackets.removeFirst()
        let packetSize = packetData.count

        // Fill output buffer
        ioNumberPackets.pointee = UInt32(1)
        packetData.withUnsafeBytes { bytes in
            ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: bytes.baseAddress)
            ioData.pointee.mBuffers.mDataByteSize = UInt32(packetSize)
        }

        return noErr
    }
}
