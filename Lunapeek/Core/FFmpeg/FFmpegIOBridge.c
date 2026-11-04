// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

#include "FFmpegIOBridge.h"
#include <libavformat/avformat.h>
#include <libavutil/mem.h>
#include <string.h>

// Context for IO operations
typedef struct {
    void *swiftContext;
    int64_t fileSize;
    int64_t position;
    int isOutput;
} IOContext;

// Read callback from Swift
extern int swiftReadCallback(void *swiftContext, uint8_t *buf, int size);
// Write callback to Swift
extern int swiftWriteCallback(void *swiftContext, const uint8_t *buf, int size);
// Seek callback from Swift
extern int64_t swiftSeekCallback(void *swiftContext, int64_t offset, int whence);

// C read callback for AVIOContext
static int readCallback(void *opaque, uint8_t *buf, int buf_size) {
    IOContext *ctx = (IOContext *)opaque;
    return swiftReadCallback(ctx->swiftContext, buf, buf_size);
}

// C write callback for AVIOContext
static int writeCallback(void *opaque, const uint8_t *buf, int buf_size) {
    IOContext *ctx = (IOContext *)opaque;
    return swiftWriteCallback(ctx->swiftContext, buf, buf_size);
}

// C seek callback for AVIOContext
static int64_t seekCallback(void *opaque, int64_t offset, int whence) {
    IOContext *ctx = (IOContext *)opaque;
    return swiftSeekCallback(ctx->swiftContext, offset, whence);
}

// Create input AVIOContext
AVIOContext *ff_create_input_io(void *swiftContext, int64_t fileSize) {
    IOContext *ctx = av_mallocz(sizeof(IOContext));
    if (!ctx) return NULL;

    ctx->swiftContext = swiftContext;
    ctx->fileSize = fileSize;
    ctx->position = 0;
    ctx->isOutput = 0;

    uint8_t *buffer = av_malloc(FF_IO_BUFFER_SIZE);
    if (!buffer) {
        av_free(ctx);
        return NULL;
    }

    AVIOContext *ioCtx = avio_alloc_context(
        buffer,
        FF_IO_BUFFER_SIZE,
        0, // read-only
        ctx,
        readCallback,
        NULL, // no write
        seekCallback
    );

    if (!ioCtx) {
        av_free(buffer);
        av_free(ctx);
        return NULL;
    }

    return ioCtx;
}

// Create output AVIOContext
AVIOContext *ff_create_output_io(void *swiftContext) {
    IOContext *ctx = av_mallocz(sizeof(IOContext));
    if (!ctx) return NULL;

    ctx->swiftContext = swiftContext;
    ctx->position = 0;
    ctx->isOutput = 1;

    uint8_t *buffer = av_malloc(FF_IO_BUFFER_SIZE);
    if (!buffer) {
        av_free(ctx);
        return NULL;
    }

    AVIOContext *ioCtx = avio_alloc_context(
        buffer,
        FF_IO_BUFFER_SIZE,
        1, // write-only
        ctx,
        NULL, // no read
        writeCallback,
        seekCallback
    );

    if (!ioCtx) {
        av_free(buffer);
        av_free(ctx);
        return NULL;
    }

    return ioCtx;
}

// Free IO context
void ff_free_io(AVIOContext *ioCtx) {
    if (!ioCtx) return;

    // Free the opaque context
    if (ioCtx->opaque) {
        av_free(ioCtx->opaque);
    }

    // avio_context_free handles the buffer
    avio_context_free(&ioCtx);
}

// Get current position
int64_t ff_io_position(AVIOContext *ioCtx) {
    if (!ioCtx) return -1;
    return ioCtx->pos;
}
