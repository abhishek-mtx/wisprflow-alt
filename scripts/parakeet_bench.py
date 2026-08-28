#!/usr/bin/env python3
"""Time NVIDIA Parakeet (MLX) on a short dictation clip for comparison with Cadence."""

from __future__ import annotations

import argparse
import time
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True, help="WAV/AIFF path")
    parser.add_argument(
        "--model",
        default="mlx-community/parakeet-tdt-0.6b-v2",
        help="Hugging Face repo id",
    )
    args = parser.parse_args()
    audio = Path(args.audio).expanduser().resolve()
    if not audio.exists():
        raise SystemExit(f"Missing audio file: {audio}")

    from parakeet_mlx import from_pretrained

    print(f"loading {args.model} …", flush=True)
    t0 = time.perf_counter()
    model = from_pretrained(args.model)
    load_ms = (time.perf_counter() - t0) * 1000
    print(f"model_load_ms={load_ms:.0f}", flush=True)

    # Warmup (compile kernels / first-graph cost)
    t1 = time.perf_counter()
    _ = model.transcribe(str(audio))
    warmup_ms = (time.perf_counter() - t1) * 1000
    print(f"warmup_transcribe_ms={warmup_ms:.0f}", flush=True)

    times = []
    text = ""
    for i in range(3):
        t2 = time.perf_counter()
        result = model.transcribe(str(audio))
        elapsed = (time.perf_counter() - t2) * 1000
        times.append(elapsed)
        text = getattr(result, "text", str(result))
        print(f"run_{i+1}_ms={elapsed:.0f}", flush=True)

    avg = sum(times) / len(times)
    print(f"steady_avg_ms={avg:.0f}")
    print(f"transcript={text.strip()[:240]}")


if __name__ == "__main__":
    main()
