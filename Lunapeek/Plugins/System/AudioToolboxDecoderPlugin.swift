// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import CoreAudio
import Foundation

/// Audio decoder using AudioToolbox/AVFoundation for AAC decoding.
public final class AudioToolboxDecoderPlugin: AudioDecoderPlugin {
    private var converter: AudioConverterRef?
    private var inputFormat: AudioStreamBasicDescription?
    private var outputFormat: AudioStreamBasicDescription?
    private var isConfigured = false
    private var pendingPackets: [MediaPacket] = []
    var currentPacket: MediaPacket?

    public init() {}

    public func configure(with formatDescription: MediaFormatDescription) async throws {
        await reset()

        guard let audioProps = formatDescription.audioProperties else {
            throw AudioDecoderError.unsupportedFormat
        }

        var input = AudioStreamBasicDescription(
            mSampleRate: Float64(audioProps.sampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(audioProps.channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var output = AudioStreamBasicDescription(
            mSampleRate: Float64(audioProps.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(audioProps.channels * 2),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(audioProps.channels * 2),
            mChannelsPerFrame: UInt32(audioProps.channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        inputFormat = input
        outputFormat = output

        var converter: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &converter)
        guard status == noErr, let converter = converter else {
            throw AudioDecoderError.configurationFailed(nil)
        }

        self.converter = converter
        isConfigured = true
    }

    public func decode(packet: MediaPacket) async throws -> AudioSamples? {
        guard isConfigured, let converter = converter, let outputFormat = outputFormat else {
            throw AudioDecoderError.notConfigured
        }

        currentPacket = packet

        var outputBufferSize: UInt32 = 8192
        var outputBuffer = Data(count: Int(outputBufferSize))
        var frames: UInt32 = 4096
        var decodeStatus: OSStatus = noErr

        outputBuffer.withUnsafeMutableBytes { outputBytes in
            var outputAudioBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: outputFormat.mChannelsPerFrame,
                    mDataByteSize: outputBufferSize,
                    mData: outputBytes.baseAddress
                )
            )

            decodeStatus = AudioConverterFillComplexBuffer(
                converter,
                inputCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                &frames,
                &outputAudioBufferList,
                nil
            )
        }

        guard decodeStatus == noErr else {
            throw AudioDecoderError.decodingFailed(nil)
        }

        let actualSize = Int(frames) * Int(outputFormat.mBytesPerFrame)
        outputBuffer.count = actualSize

        return AudioSamples(
            data: outputBuffer,
            sampleCount: Int(frames),
            presentationTimestamp: packet.presentationTimestamp,
            duration: packet.duration,
            format: outputFormat
        )
    }

    private func fillInputData(
        ioData: UnsafeMutablePointer<AudioBufferList>,
        ioDataSize: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        guard let packet = currentPacket else {
            ioDataSize.pointee = 0
            return noErr
        }

        let bufferSize = min(UInt32(packet.data.count), ioDataSize.pointee)
        packet.data.withUnsafeBytes { bytes in
            memcpy(ioData.pointee.mBuffers.mData, bytes.baseAddress, Int(bufferSize))
        }

        ioData.pointee.mBuffers.mDataByteSize = bufferSize
        ioDataSize.pointee = bufferSize
        currentPacket = nil

        return noErr
    }

    public func flush() async throws -> AudioSamples? {
        return nil
    }

    public func reset() async {
        if let converter = converter {
            AudioConverterDispose(converter)
        }
        converter = nil
        inputFormat = nil
        outputFormat = nil
        pendingPackets.removeAll()
        currentPacket = nil
        isConfigured = false
    }

    public static func supports(codec: String) -> Bool {
        let supportedCodecs = ["aac", "mp4a", "aac-lc", "he-aac"]
        return supportedCodecs.contains(codec.lowercased())
    }
}

private let inputCallback: @convention(c) (
    AudioConverterRef,
    UnsafeMutablePointer<UInt32>,
    UnsafeMutablePointer<AudioBufferList>,
    UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    UnsafeMutableRawPointer?
) -> OSStatus = { converter, ioNumberDataPackets, ioData, outDataPacketDescriptions, inUserData in
    guard let inUserData = inUserData else {
        ioNumberDataPackets.pointee = 0
        return noErr
    }
    let decoder = Unmanaged<AudioToolboxDecoderPlugin>.fromOpaque(inUserData).takeUnretainedValue()

    ioNumberDataPackets.pointee = 1
    ioData.pointee.mNumberBuffers = 1

    guard let packet = decoder.currentPacket else {
        ioNumberDataPackets.pointee = 0
        return noErr
    }

    let dataSize = UInt32(packet.data.count)
    packet.data.withUnsafeBytes { bytes in
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: bytes.baseAddress)
        ioData.pointee.mBuffers.mDataByteSize = dataSize
    }

    decoder.currentPacket = nil
    return noErr
}
