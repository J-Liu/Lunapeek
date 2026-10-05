// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import AudioToolbox
import Foundation

/// Audio renderer using AudioQueue.
public final class AudioRenderer {
    private var audioQueue: AudioQueueRef?
    private var audioFormat: AudioStreamBasicDescription?
    private var buffers: [AudioQueueBufferRef?] = []
    private var isPlaying = false
    private var pendingSamples: [AudioSamples] = []

    public init() {}

    public func configure(with formatDescription: MediaFormatDescription?) {
        guard let audioProps = formatDescription?.audioProperties else { return }

        audioFormat = AudioStreamBasicDescription(
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

        createAudioQueue()
    }

    private func createAudioQueue() {
        guard let format = audioFormat else { return }

        var desc = format
        let status = AudioQueueNewOutput(
            &desc,
            audioQueueOutputCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            CFRunLoopGetCurrent(),
            CFRunLoopMode.commonModes.rawValue,
            0,
            &audioQueue
        )

        guard status == noErr, let queue = audioQueue else { return }

        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(queue, 8192, &buffer)
            if let buffer = buffer {
                buffers.append(buffer)
            }
        }
    }

    public func enqueue(_ samples: AudioSamples) {
        pendingSamples.append(samples)
        processPendingSamples()
    }

    private func processPendingSamples() {
        guard let queue = audioQueue, isPlaying else { return }

        while !pendingSamples.isEmpty {
            var bufferToUse: AudioQueueBufferRef?
            for buffer in buffers {
                if let buffer = buffer, buffer.pointee.mAudioDataByteSize == 0 {
                    bufferToUse = buffer
                    break
                }
            }

            guard let buffer = bufferToUse else { break }

            let samples = pendingSamples.removeFirst()
            let copySize = min(samples.data.count, Int(buffer.pointee.mAudioDataBytesCapacity))
            samples.data.withUnsafeBytes { bytes in
                memcpy(buffer.pointee.mAudioData, bytes.baseAddress, copySize)
            }
            buffer.pointee.mAudioDataByteSize = UInt32(copySize)

            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
    }

    public func play() {
        guard let queue = audioQueue, !isPlaying else { return }
        AudioQueueStart(queue, nil)
        isPlaying = true
        processPendingSamples()
    }

    public func pause() {
        guard let queue = audioQueue, isPlaying else { return }
        AudioQueuePause(queue)
        isPlaying = false
    }

    public func flush() {
        guard let queue = audioQueue else { return }
        AudioQueueFlush(queue)
        pendingSamples.removeAll()
    }

    public func reset() {
        flush()
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }
        audioQueue = nil
        buffers.removeAll()
        isPlaying = false
    }
}

private func audioQueueOutputCallback(
    _ inUserData: UnsafeMutableRawPointer?,
    _ inAQ: AudioQueueRef,
    _ inBuffer: AudioQueueBufferRef
) {
    inBuffer.pointee.mAudioDataByteSize = 0
}