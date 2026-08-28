#!/usr/bin/env python3
"""Keep Parakeet loaded and transcribe WAV paths from stdin (one JSON line in, one out)."""

from __future__ import annotations

import json
import sys
import time

MODEL_ID = "mlx-community/parakeet-tdt-0.6b-v2"


def main() -> None:
    from parakeet_mlx import from_pretrained

    t0 = time.perf_counter()
    model = from_pretrained(MODEL_ID)
    load_ms = round((time.perf_counter() - t0) * 1000)
    print(json.dumps({"event": "ready", "load_ms": load_ms, "model": MODEL_ID}), flush=True)

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as exc:
            print(json.dumps({"event": "error", "error": str(exc)}), flush=True)
            continue
        if msg.get("cmd") == "quit":
            break
        path = msg.get("path")
        if not path:
            print(json.dumps({"event": "error", "error": "missing path"}), flush=True)
            continue
        t1 = time.perf_counter()
        result = model.transcribe(path)
        ms = round((time.perf_counter() - t1) * 1000)
        text = getattr(result, "text", str(result)).strip()
        print(
            json.dumps(
                {
                    "event": "result",
                    "transcript": text,
                    "latency_ms": ms,
                    "load_ms": load_ms,
                }
            ),
            flush=True,
        )


if __name__ == "__main__":
    main()
