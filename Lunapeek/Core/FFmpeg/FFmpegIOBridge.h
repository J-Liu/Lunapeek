// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

#ifndef FFMPEG_IO_BRIDGE_H
#define FFMPEG_IO_BRIDGE_H

#include <libavformat/avformat.h>
#include <stdint.h>

// Buffer size for IO
#define FF_IO_BUFFER_SIZE 65536

// Create input AVIOContext for reading
AVIOContext *ff_create_input_io(void *swiftContext, int64_t fileSize);

// Create output AVIOContext for writing
AVIOContext *ff_create_output_io(void *swiftContext);

// Free IO context
void ff_free_io(AVIOContext *ioCtx);

// Get current position
int64_t ff_io_position(AVIOContext *ioCtx);

#endif // FFMPEG_IO_BRIDGE_H
