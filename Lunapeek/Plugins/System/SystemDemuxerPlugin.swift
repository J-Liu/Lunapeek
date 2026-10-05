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
        close()
        currentURL = url

        let asset = AVAsset(url: url)
        self.asset = asset

        try await asset.loadValues(forKeys: ["tracks", "duration"])

        guard try await asset.statusOfValue(forKey: "tracks") == .loaded else {
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
        let duration = try await track.load(.duration)
        let timeRange = try await track.load(.timeRange)

        var formatDescription: MediaFormatDescription?
        let formatDescriptions = try await track.load(.formatDescriptions)

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
        let codecTypeStr = CMFormatDescriptionGetMediaSubTypeString(desc)
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
                    channels: asbd.mChannelsPerFrame,
                    bitsPerSample: asbd.mBitsPerChannel
                )
            }
        }

        return MediaFormatDescription(
            codecName: codecTypeStr ?? "unknown",
            codecId: codecId,
            videoProperties: videoProps,
            audioProperties: audioProps
        )
    }

    public func readPacket() async throws -> MediaPacket? {
        guard let reader = assetReader, reader.status == .reading else {
            if reader?.status == .completed {
                return nil
            }
            throw DemuxerError.readerError(reader?.error)
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
        CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: data.bytes)

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        let isKeyFrame = sampleBuffer.numSamples > 0 &&
            !sampleBuffer.sampleAttachmentsEntries.isEmpty &&
            (sampleBuffer.sampleAttachmentsEntries.first?.first?.sampleAttachment.keys.contains(.notSync) == false ||
             sampleBuffer.sampleAttachmentsEntries.first?.first?.sampleAttachment[.notSync] as? Bool != true)

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

        close()
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

private extension Data {
    var bytes: [UInt8] {
        withUnsafeBytes { Array($0) }
    }
}
