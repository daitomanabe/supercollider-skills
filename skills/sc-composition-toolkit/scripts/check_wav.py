#!/usr/bin/env python3
"""Stream-check RIFF/WAVE PCM and IEEE float audio using only the standard library."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import sys


def inspect_wav(path: Path) -> dict:
    with path.open("rb") as stream:
        header = stream.read(12)
        if len(header) != 12 or header[:4] != b"RIFF" or header[8:] != b"WAVE":
            raise ValueError("Expected RIFF/WAVE (RF64 and compressed files are unsupported)")
        file_size = path.stat().st_size
        riff_end = 8 + struct.unpack_from("<I", header, 4)[0]
        if riff_end > file_size or riff_end < 12:
            raise ValueError("Truncated or invalid RIFF container")
        fmt = None
        data = None
        while stream.tell() + 8 <= riff_end:
            chunk_id, size = struct.unpack("<4sI", stream.read(8))
            start = stream.tell()
            if start + size > riff_end:
                raise ValueError("Truncated WAV chunk")
            if chunk_id == b"fmt ":
                if size < 16 or size > 4096:
                    raise ValueError("Unsupported WAV format header size")
                fmt = stream.read(size)
            elif chunk_id == b"data":
                if data is not None:
                    raise ValueError("Multiple data chunks are unsupported")
                data = (start, size)
            stream.seek(start + size + size % 2)
        if fmt is None or data is None:
            raise ValueError("Missing fmt or data chunk")
        encoding, channels, rate, byte_rate, alignment, bits = struct.unpack_from("<HHIIHH", fmt)
        if encoding == 65534:
            if len(fmt) < 40 or struct.unpack_from("<H", fmt, 16)[0] < 22:
                raise ValueError("Invalid WAVE extensible format")
            guid = fmt[24:40]
            if guid[4:] != bytes.fromhex("00001000800000aa00389b71"):
                raise ValueError("Unsupported WAVE extensible subtype")
            encoding = struct.unpack_from("<I", guid)[0]
            valid_bits = struct.unpack_from("<H", fmt, 18)[0]
            if valid_bits not in (0, bits):
                raise ValueError("Packed valid-bit formats are unsupported")
        supported = (encoding == 1 and bits in (8, 16, 24, 32)) or (encoding == 3 and bits in (32, 64))
        width = bits // 8
        if not supported or channels < 1 or rate < 1 or alignment != channels * width or byte_rate != rate * alignment:
            raise ValueError("Unsupported encoding or inconsistent WAV format")
        offset, data_size = data
        if data_size == 0 or data_size % alignment:
            raise ValueError("Empty or frame-misaligned WAV data")
        frames = data_size // alignment
        stream.seek(offset)
        left = data_size
        peak = square_sum = 0.0
        finite_count = nonfinite = full_scale = 0
        while left:
            block = stream.read(min(left, alignment * 16384))
            if not block:
                raise ValueError("Truncated WAV data")
            left -= len(block)
            if encoding == 3:
                values = (item[0] for item in struct.iter_unpack("<f" if bits == 32 else "<d", block))
                positive_limit = 1.0
            elif bits == 8:
                values = ((value - 128) / 128 for value in block)
                positive_limit = 127 / 128
            else:
                scale = 2 ** (bits - 1)
                values = (int.from_bytes(block[i:i + width], "little", signed=True) / scale
                          for i in range(0, len(block), width))
                positive_limit = (scale - 1) / scale
            for value in values:
                if not math.isfinite(value):
                    nonfinite += 1
                    continue
                finite_count += 1
                peak = max(peak, abs(value))
                square_sum += value * value
                full_scale += value >= positive_limit or value <= -1
        rms = math.sqrt(square_sum / finite_count) if finite_count else 0.0
        return {"path": str(path), "channels": channels, "sample_rate": rate, "bits_per_sample": bits,
                "encoding": "PCM" if encoding == 1 else "IEEE_FLOAT", "frames": frames,
                "duration_seconds": frames / rate, "peak": peak,
                "peak_dbfs": 20 * math.log10(peak) if peak else None,
                "rms_dbfs": 20 * math.log10(rms) if rms else None,
                "nonfinite_samples": nonfinite, "full_scale_samples": full_scale}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--channels", type=int)
    parser.add_argument("--sample-rate", type=int)
    parser.add_argument("--duration", type=float)
    parser.add_argument("--duration-tolerance", type=float, default=0.01)
    parser.add_argument("--max-peak-db", type=float, help="Optional headroom ceiling, in dBFS")
    parser.add_argument("--allow-silence", action="store_true")
    args = parser.parse_args()
    for name in ("duration", "duration_tolerance", "max_peak_db"):
        value = getattr(args, name)
        if value is not None and not math.isfinite(value):
            parser.error(f"--{name.replace('_', '-')} must be finite")
    if args.duration_tolerance < 0 or (args.duration is not None and args.duration <= 0):
        parser.error("Duration must be positive and tolerance nonnegative")
    try:
        result = inspect_wav(args.path)
        failures = []
        if args.channels is not None and result["channels"] != args.channels:
            failures.append("Unexpected channel count")
        if args.sample_rate is not None and result["sample_rate"] != args.sample_rate:
            failures.append("Unexpected sample rate")
        if args.duration is not None and abs(result["duration_seconds"] - args.duration) > args.duration_tolerance:
            failures.append("Unexpected duration")
        if result["nonfinite_samples"]:
            failures.append("Nonfinite samples")
        if result["full_scale_samples"]:
            failures.append("Full-scale samples: possible clipping")
        if not args.allow_silence and result["peak"] == 0:
            failures.append("Digital silence")
        if args.max_peak_db is not None and result["peak_dbfs"] is not None and result["peak_dbfs"] > args.max_peak_db:
            failures.append("Peak exceeds requested ceiling")
        result.update(status="PASS" if not failures else "FAIL", failures=failures)
        print(json.dumps(result, indent=2, allow_nan=False))
        return bool(failures)
    except (OSError, ValueError, struct.error) as error:
        print(json.dumps({"status": "FAIL", "error": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
