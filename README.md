# Lunapeek

A gentle player for common formats.

## Overview

Lunapeek is an iOS video player with a plugin architecture that supports multiple container formats and codecs through a protocol-based design.

## Architecture

### Core Layers

- **Core/Plugins** - Protocol definitions for demuxer, video decoder, and audio decoder
- **Core/Player** - Player engine coordinating all components
- **Core/Renderer** - Video and audio rendering with A/V synchronization

### Plugin System

- **DemuxerPlugin** - Container format support (MP4, MKV, FLV, TS, etc.)
- **VideoDecoderPlugin** - Video codec support (H.264, HEVC, VP9, etc.)
- **AudioDecoderPlugin** - Audio codec support (AAC, MP3, FLAC, etc.)

### Implementations

#### System Plugins
- `SystemDemuxerPlugin` - AVAssetReader-based demuxer for MP4/MOV
- `VideoToolboxDecoderPlugin` - Hardware-accelerated H.264/HEVC decoding
- `AudioToolboxDecoderPlugin` - AAC audio decoding

#### FFmpeg Plugins (requires build)
- `FFmpegDemuxerPlugin` - MKV, FLV, TS, and network protocols
- `FFmpegVideoDecoderPlugin` - Software video decoding
- `FFmpegAudioDecoderPlugin` - Software audio decoding

## Building

### Prerequisites
- Xcode 27.0+
- iOS 12.1+ SDK

### Build FFmpeg (optional)

```bash
./build.sh
```

This builds FFmpeg as a local Swift Package with:
- VideoToolbox hardware acceleration
- AudioToolbox support
- AVFoundation integration
- No GPL libraries

### Open in Xcode

```bash
open Lunapeek.xcodeproj
```

## Features

- [x] MP4/MOV playback via system frameworks
- [x] H.264/HEVC hardware decoding
- [x] AAC audio playback
- [x] Background audio playback
- [ ] MKV/FLV/TS support (requires FFmpeg)
- [ ] Network streaming (SFTP/SMB)
- [ ] Audio-only file support
- [ ] Subtitle support

## Project Structure

```
Lunapeek/
├── Core/
│   ├── Plugins/       # Protocol definitions
│   ├── Player/        # Player engine
│   └── Renderer/      # Video/audio renderers
├── Plugins/
│   ├── System/        # System-based implementations
│   └── FFmpeg/        # FFmpeg-based implementations
└── Network/
    ├── SFTP/          # SFTP client
    └── SMB/           # SMB client
```

## License

This project is licensed under the **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**, with an **additional permission under Section 7** allowing distribution through app stores under certain conditions.

See [LICENSE](LICENSE) for the full license text and the exact wording of the additional permission.

## Copyright

Copyright 2026 Jia Liu. All rights reserved.
