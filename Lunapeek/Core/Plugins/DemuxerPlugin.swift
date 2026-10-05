// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import Foundation

/// Represents a media packet extracted from a container.
public struct MediaPacket {
    public let data: Data
    public let streamIndex: Int
    public let presentationTimestamp: Int64
    public let decodingTimestamp: Int64
    public let duration: Int64
    public let isKeyFrame: Bool

    public init(
        data: Data,
        streamIndex: Int,
        presentationTimestamp: Int64,
        decodingTimestamp: Int64,
        duration: Int64,
        isKeyFrame: Bool
    ) {
        self.data = data
        self.streamIndex = streamIndex
        self.presentationTimestamp = presentationTimestamp
        self.decodingTimestamp = decodingTimestamp
        self.duration = duration
        self.isKeyFrame = isKeyFrame
    }
}

/// Represents stream information within a container.
public struct StreamInfo {
    public let index: Int
    public let codecType: CodecType
    public let formatDescription: MediaFormatDescription
    public let duration: Int64
    public let timeBase: TimeBase

    public init(
        index: Int,
        codecType: CodecType,
        formatDescription: MediaFormatDescription,
        duration: Int64,
        timeBase: TimeBase
    ) {
        self.index = index
        self.codecType = codecType
        self.formatDescription = formatDescription
        self.duration = duration
        self.timeBase = timeBase
    }
}

/// Codec type enumeration.
public enum CodecType {
    case video
    case audio
    case subtitle
    case unknown
}

/// Time base for timestamp conversion.
public struct TimeBase {
    public let numerator: Int32
    public let denominator: Int32

    public init(numerator: Int32, denominator: Int32) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let defaultTimeBase = TimeBase(numerator: 1, denominator: 1000000)
}

/// Abstract format description wrapper.
public struct MediaFormatDescription {
    public let codecName: String
    public let codecId: UInt32
    public let extradata: Data?
    public let videoProperties: VideoFormatProperties?
    public let audioProperties: AudioFormatProperties?

    public init(
        codecName: String,
        codecId: UInt32,
        extradata: Data? = nil,
        videoProperties: VideoFormatProperties? = nil,
        audioProperties: AudioFormatProperties? = nil
    ) {
        self.codecName = codecName
        self.codecId = codecId
        self.extradata = extradata
        self.videoProperties = videoProperties
        self.audioProperties = audioProperties
    }
}

/// Video format properties.
public struct VideoFormatProperties {
    public let width: Int32
    public let height: Int32
    public let pixelFormat: String?
    public let frameRate: Double

    public init(width: Int32, height: Int32, pixelFormat: String? = nil, frameRate: Double = 0) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.frameRate = frameRate
    }
}

/// Audio format properties.
public struct AudioFormatProperties {
    public let sampleRate: Int32
    public let channels: Int32
    public let bitsPerSample: Int32
    public let format: String?

    public init(sampleRate: Int32, channels: Int32, bitsPerSample: Int32, format: String? = nil) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.format = format
    }
}

/// Container metadata.
public struct ContainerInfo {
    public let duration: Int64
    public let bitRate: Int64
    public let streams: [StreamInfo]
    public let metadata: [String: String]

    public init(duration: Int64, bitRate: Int64, streams: [StreamInfo], metadata: [String: String] = [:]) {
        self.duration = duration
        self.bitRate = bitRate
        self.streams = streams
        self.metadata = metadata
    }
}

/// Demuxer plugin protocol - responsible for extracting media packets from containers.
public protocol DemuxerPlugin {
    /// Opens a media container from the specified URL.
    func open(url: URL) async throws -> ContainerInfo

    /// Reads the next media packet from the container.
    func readPacket() async throws -> MediaPacket?

    /// Seeks to the specified timestamp (in microseconds).
    func seek(to timestamp: Int64) async throws

    /// Closes the container and releases resources.
    func close() async

    /// Returns whether this plugin supports the given URL scheme.
    static func supports(url: URL) -> Bool
}