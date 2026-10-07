// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import Foundation

/// System demuxer using AVAssetReader for MP4/MOV containers.
public final class SystemDemuxerPlugin: DemuxerPlugin {
    private var asset: AVAsset?
    private var assetReader: AVAssetReader?
    private var outputMap: [Int: AVAssetReaderTrackOutput] = [:]
    private var containerInfo: ContainerInfo?
    private var currentURL: URL?

    public init() {}

    public func open(url: URL) async throws -> ContainerInfo {
        await close()
        currentURL = url

        let asset = AVAsset(url: url)
        self.asset = asset

        try await asset.loadValues(forKeys: ["tracks", "duration"])

        var error: NSError?
        let status = asset.statusOfValue(forKey: "tracks", error: &error)
        guard status == .loaded else {
            throw DemuxerError.failedToLoadTracks
        }

        let reader = try AVAssetReader(asset: asset)
        assetReader = reader

        var streams: [StreamInfo] = []
        let tracks = try await asset.loadTracks(withMediaCharacteristic: .visual)

        for (index, track) in tracks.enumerated() {
            let settings: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: nil
            )
            output.alwaysCopiesSampleData = true
            reader.add(output)
            outputMap[index] = output

            let trackInfo = try await buildStreamInfo(for: track, index: index, codecType: .video)
            streams.append(trackInfo)
        }

        let audioTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
        for (index, track) in audioTracks.enumerated() {
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: nil
            )
            output.alwaysCopiesSampleData = true
            reader.add(output)
            let streamIndex = tracks.count + index
            outputMap[streamIndex] = output

            let trackInfo = try await buildStreamInfo(for: track, index: streamIndex, codecType: .audio)
            streams.append(trackInfo)
        }

        guard reader.startReading() else {
            throw DemuxerError.failedToStartReading(reader.error)
        }

        let duration = try await asset.load(.duration)
        let info = ContainerInfo(
            duration: CMTimeGetSeconds(duration).times(1_000_000),
            bitRate: 0,
            streams: streams
        )
        containerInfo = info
        return info
    }

    private func buildStreamInfo(for track: AVAssetTrack, index: Int, codecType: CodecType) async throws -> StreamInfo {
        // Load track properties using string keys to avoid static member lookup conflict
        try await track.loadValues(forKeys: ["timeRange", "formatDescriptions"])

        // Use timeRange.duration since duration property is unavailable in Swift
        let timeRange = track.timeRange
        let duration = timeRange.duration

        var formatDescription: MediaFormatDescription?
        // formatDescriptions returns [Any], need to cast
        let formatDescriptions = track.formatDescriptions as? [CMFormatDescription] ?? []

        if let desc = formatDescriptions.first {
            formatDescription = buildFormatDescription(from: desc, codecType: codecType)
        }

        return StreamInfo(
            index: index,
            codecType: codecType,
            formatDescription: formatDescription ?? MediaFormatDescription(
                codecName: "unknown",
                codecId: 0
            ),
            duration: CMTimeGetSeconds(duration).times(1_000_000),
            timeBase: TimeBase.defaultTimeBase
        )
    }

    private func buildFormatDescription(from desc: CMFormatDescription, codecType: CodecType) -> MediaFormatDescription {
        let codecTypeStr = String(fourCharCode: CMFormatDescriptionGetMediaSubType(desc))
        let codecId = CMFormatDescriptionGetMediaSubType(desc)
        let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any]

        var videoProps: VideoFormatProperties?
        var audioProps: AudioFormatProperties?

        if codecType == .video {
            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            videoProps = VideoFormatProperties(
                width: dimensions.width,
                height: dimensions.height
            )
        } else if codecType == .audio {
            let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
            if let asbd = basicDesc?.pointee {
                audioProps = AudioFormatProperties(
                    sampleRate: Int32(asbd.mSampleRate),
                    channels: Int32(asbd.mChannelsPerFrame),
                    bitsPerSample: Int32(asbd.mBitsPerChannel)
                )
            }
        }

        return MediaFormatDescription(
            codecName: codecTypeStr,
            codecId: codecId,
            videoProperties: videoProps,
            audioProperties: audioProps
        )
    }

    public func readPacket() async throws -> MediaPacket? {
        guard let assetReader, assetReader.status == .reading else {
            if assetReader?.status == .completed {
                return nil
            }
            throw DemuxerError.readerError(assetReader?.error)
        }

        for (streamIndex, output) in outputMap {
            if let sampleBuffer = output.copyNextSampleBuffer() {
                let packet = buildPacket(from: sampleBuffer, streamIndex: streamIndex)
                return packet
            }
        }

        return nil
    }

    private func buildPacket(from sampleBuffer: CMSampleBuffer, streamIndex: Int) -> MediaPacket {
        let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
        var data = Data()
        let length = CMBlockBufferGetDataLength(dataBuffer)
        data.reserveCapacity(length)
        data.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        let isKeyFrame: Bool
        if sampleBuffer.numSamples > 0 {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            if let attachments, CFArrayGetCount(attachments) > 0 {
                let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
                let notSync = CFDictionaryGetValue(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
                isKeyFrame = notSync == nil
            } else {
                isKeyFrame = true
            }
        } else {
            isKeyFrame = false
        }

        return MediaPacket(
            data: data,
            streamIndex: streamIndex,
            presentationTimestamp: CMTimeGetSeconds(pts).times(1_000_000),
            decodingTimestamp: CMTimeGetSeconds(dts).times(1_000_000),
            duration: CMTimeGetSeconds(duration).times(1_000_000),
            isKeyFrame: isKeyFrame
        )
    }

    public func seek(to timestamp: Int64) async throws {
        guard let asset = asset else {
            throw DemuxerError.noAsset
        }

        await close()
        let newReader = try AVAssetReader(asset: asset)

        let time = CMTime(
            seconds: Double(timestamp) / 1_000_000,
            preferredTimescale: 1_000_000
        )

        for (_, output) in outputMap {
            output.reset(forReadingTimeRanges: [NSValue(timeRange: CMTimeRange(start: time, duration: .positiveInfinity))])
            newReader.add(output)
        }

        guard newReader.startReading() else {
            throw DemuxerError.failedToStartReading(newReader.error)
        }
        assetReader = newReader
    }

    public func close() async {
        assetReader?.cancelReading()
        assetReader = nil
        outputMap.removeAll()
    }

    public static func supports(url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "3gp"].contains(pathExtension)
    }
}

public enum DemuxerError: Error {
    case failedToLoadTracks
    case failedToStartReading(Error?)
    case readerError(Error?)
    case noAsset
}

private extension Double {
    func times(_ multiplier: Int64) -> Int64 {
        Int64(self * Double(multiplier))
    }
}

private extension String {
    init(fourCharCode: FourCharCode) {
        var code = fourCharCode.bigEndian
        self = withUnsafeBytes(of: &code) { Data($0).map { Character(UnicodeScalar($0)) } }.map { String($0) }.joined()
    }
}
