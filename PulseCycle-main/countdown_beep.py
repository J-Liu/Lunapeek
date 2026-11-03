#!/bin/python
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright 2026 Jia Liu
# Licensed under AGPL-3.0-or-later with an additional permission
# under Section 7. See LICENSE for details.

import math
import struct
import wave

def generate_beep(path, frequency=880.0, duration_ms=80, sample_rate=44100, volume=0.6):
    n_samples = int(sample_rate * duration_ms / 1000)
    fade_samples = int(sample_rate * 0.005)
    frames = bytearray()

    for i in range(n_samples):
        t = i / sample_rate

        sample = math.sin(2 * math.pi * frequency * t)

        if i < fade_samples:
            env = i / fade_samples
        elif i > n_samples - fade_samples:
            env = (n_samples - i) / fade_samples
        else:
            env = 1.0
        sample *= env * volume

        value = int(sample * 32767)
        frames += struct.pack('<h', value)

    with wave.open(path, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(frames)
    print(f"wrote {path}")

if __name__ == "__main__":
    generate_beep("countdown_beep.wav", frequency=880.0, duration_ms=80, volume=0.6)
