#!/usr/bin/env python3
"""Side-by-side mic test: macOS 26 SpeechTranscriber vs Parakeet TDT (MLX)."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
import wave
from difflib import SequenceMatcher
from pathlib import Path

import gradio as gr

ROOT = Path(__file__).resolve().parent
VENV_PYTHON = ROOT / ".venv-parakeet" / "bin" / "python"
APPLE_BIN = ROOT / "bin" / "apple-speech-transcribe"
PARAKEET_ID = "mlx-community/parakeet-tdt-0.6b-v2"
HF_CACHE = Path.home() / ".cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v2"

_parakeet_model = None
_parakeet_load_ms = None
_parakeet_error = None


def _ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if found:
        return found
    brew = Path("/opt/homebrew/bin/ffmpeg")
    if brew.exists():
        return str(brew)
    raise RuntimeError("ffmpeg is required to normalize recordings")


def ensure_wav(src: str | Path) -> Path:
    src = Path(src)
    dest = src.with_suffix(".bench.wav")
    cmd = [
        _ffmpeg(),
        "-y",
        "-i",
        str(src),
        "-ac",
        "1",
        "-ar",
        "16000",
        "-c:a",
        "pcm_s16le",
        str(dest),
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    return dest


def wav_seconds(path: Path) -> float:
    with wave.open(str(path), "rb") as handle:
        return handle.getnframes() / float(handle.getframerate() or 1)


def load_parakeet():
    global _parakeet_model, _parakeet_load_ms, _parakeet_error
    if _parakeet_model is not None:
        return _parakeet_model
    from parakeet_mlx import from_pretrained

    t0 = time.perf_counter()
    _parakeet_model = from_pretrained(PARAKEET_ID)
    _parakeet_load_ms = (time.perf_counter() - t0) * 1000
    return _parakeet_model


def run_parakeet(wav: Path) -> dict:
    model = load_parakeet()
    t0 = time.perf_counter()
    result = model.transcribe(str(wav))
    ms = (time.perf_counter() - t0) * 1000
    text = getattr(result, "text", str(result)).strip()
    seconds = wav_seconds(wav)
    return {
        "engine": "parakeet-tdt-0.6b-v2",
        "transcript": text,
        "latency_ms": round(ms),
        "first_partial_ms": None,
        "audio_seconds": round(seconds, 3),
        "rtf": round((ms / 1000.0) / seconds, 3) if seconds else 0,
        "error": None,
        "source": PARAKEET_ID,
        "load_ms": round(_parakeet_load_ms or 0),
    }


def run_apple(wav: Path) -> dict:
    if not APPLE_BIN.exists():
        return {
            "engine": "apple-speech-transcriber",
            "transcript": "",
            "latency_ms": 0,
            "first_partial_ms": None,
            "audio_seconds": wav_seconds(wav),
            "rtf": 0,
            "error": f"Missing {APPLE_BIN}. Compile scripts/apple_speech_transcribe.swift first.",
            "source": "SpeechAnalyzer + SpeechTranscriber",
        }
    env = os.environ.copy()
    env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:" + env.get("PATH", "")
    t0 = time.perf_counter()
    proc = subprocess.run(
        [str(APPLE_BIN), str(wav), "en-US"],
        capture_output=True,
        text=True,
        env=env,
        timeout=120,
    )
    wall_ms = (time.perf_counter() - t0) * 1000
    if proc.returncode != 0 and not proc.stdout.strip():
        return {
            "engine": "apple-speech-transcriber",
            "transcript": "",
            "latency_ms": round(wall_ms),
            "error": (proc.stderr or "Apple Speech CLI failed").strip(),
            "source": "SpeechAnalyzer + SpeechTranscriber",
        }
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {
            "engine": "apple-speech-transcriber",
            "transcript": "",
            "latency_ms": round(wall_ms),
            "error": proc.stdout[:400] or proc.stderr,
            "source": "SpeechAnalyzer + SpeechTranscriber",
        }
    payload["source"] = "SpeechAnalyzer + SpeechTranscriber"
    payload["wall_ms"] = round(wall_ms)
    return payload


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def word_error_rate(reference: str, hypothesis: str) -> float | None:
    ref = words(reference)
    hyp = words(hypothesis)
    if not ref:
        return None
    matcher = SequenceMatcher(a=ref, b=hyp)
    matches = sum(block.size for block in matcher.get_matching_blocks())
    return round(1.0 - (matches / len(ref)), 3)


def agreement(a: str, b: str) -> float | None:
    wa, wb = words(a), words(b)
    if not wa and not wb:
        return None
    matcher = SequenceMatcher(a=wa, b=wb)
    denom = max(len(wa), len(wb), 1)
    return round(sum(block.size for block in matcher.get_matching_blocks()) / denom, 3)


def diff_markdown(apple: str, parakeet: str) -> str:
    a_w, b_w = apple.split(), parakeet.split()
    matcher = SequenceMatcher(a=a_w, b=b_w)
    apple_bits: list[str] = []
    para_bits: list[str] = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            chunk = " ".join(a_w[i1:i2])
            apple_bits.append(chunk)
            para_bits.append(chunk)
        elif tag == "replace":
            apple_bits.append(f"**{(' '.join(a_w[i1:i2]))}**")
            para_bits.append(f"**{(' '.join(b_w[j1:j2]))}**")
        elif tag == "delete":
            apple_bits.append(f"~~{' '.join(a_w[i1:i2])}~~")
        elif tag == "insert":
            para_bits.append(f"**{' '.join(b_w[j1:j2])}**")
    return (
        "**Word-level differences** (bold = disagree, strike = only on Apple)\n\n"
        f"*Apple:* {' '.join(apple_bits) or '—'}\n\n"
        f"*Parakeet:* {' '.join(para_bits) or '—'}"
    )


def engine_card(title: str, result: dict, reference: str) -> str:
    err = result.get("error")
    if err:
        return f"### {title}\n\n**Error:** {err}"
    transcript = result.get("transcript") or "—"
    latency = result.get("latency_ms", 0)
    rtf = result.get("rtf", 0)
    try:
        rtf = round(float(rtf), 3)
    except (TypeError, ValueError):
        pass
    first = result.get("first_partial_ms")
    first_line = f"*First partial:* {first} ms" if first else "*First partial:* n/a (file decode)"
    wer_line = ""
    if reference.strip():
        wer = word_error_rate(reference, transcript)
        if wer is not None:
            wer_line = f"\n*WER vs your script:* **{wer:.1%}**"
    return (
        f"### {title}\n\n"
        f"{transcript}\n\n"
        f"*Latency:* **{latency} ms**  ·  *RTF:* **{rtf}**  ·  {first_line}"
        f"{wer_line}\n\n"
        f"*Source:* `{result.get('source', '')}`"
    )


def compare(audio, reference: str):
    if not audio:
        empty = "Record a clip first."
        return empty, empty, empty, empty
    wav = ensure_wav(audio)
    seconds = wav_seconds(wav)
    apple = run_apple(wav)
    parakeet = run_parakeet(wav)

    apple_md = engine_card("macOS 26 Speech Transcriber", apple, reference or "")
    para_md = engine_card("Parakeet TDT 0.6b (MLX)", parakeet, reference or "")

    apple_ok = not apple.get("error") and apple.get("transcript")
    para_ok = not parakeet.get("error") and parakeet.get("transcript")
    summary_lines = [
        f"**Clip:** {seconds:.2f}s  ·  16 kHz mono WAV",
        f"**Apple:** {apple.get('latency_ms', 0)} ms"
        + (f"  ·  first partial {apple.get('first_partial_ms')} ms" if apple.get("first_partial_ms") else ""),
        f"**Parakeet:** {parakeet.get('latency_ms', 0)} ms"
        + (f"  ·  weights already cached ({parakeet.get('load_ms', 0)} ms to attach)" if parakeet.get("load_ms") else ""),
    ]
    if apple_ok and para_ok:
        agree = agreement(apple["transcript"], parakeet["transcript"])
        if agree is not None:
            summary_lines.append(f"**Transcript agreement:** {agree:.0%}")
        a_ms = apple.get("latency_ms") or 0
        p_ms = parakeet.get("latency_ms") or 0
        if a_ms and p_ms:
            if p_ms < a_ms:
                summary_lines.append(f"**Faster engine:** Parakeet ({a_ms / p_ms:.1f}×)")
            elif a_ms < p_ms:
                summary_lines.append(f"**Faster engine:** Apple Speech ({p_ms / a_ms:.1f}×)")
        summary_lines.append(diff_markdown(apple["transcript"], parakeet["transcript"]))
    if reference.strip():
        for name, result in (("Apple", apple), ("Parakeet", parakeet)):
            if result.get("transcript"):
                wer = word_error_rate(reference, result["transcript"])
                if wer is not None:
                    summary_lines.append(f"**{name} WER:** {wer:.1%}")

    hf_status = (
        "Parakeet weights are already on disk — no Hub download on this run.\n\n"
        if HF_CACHE.exists()
        else "Parakeet will download from Hugging Face Hub on first load.\n\n"
    )
    how = (
        hf_status
        + "```python\n"
        + "from huggingface_hub import hf_hub_download\n"
        + "from parakeet_mlx import from_pretrained\n\n"
        + f'model = from_pretrained("{PARAKEET_ID}")\n'
        + "# internally:\n"
        + f'#   hf_hub_download("{PARAKEET_ID}", "config.json")\n'
        + f'#   hf_hub_download("{PARAKEET_ID}", "model.safetensors")\n'
        + "```\n\n"
        + f"Cache: `{HF_CACHE}`"
    )
    return apple_md, para_md, "\n\n".join(summary_lines), how


def startup_status() -> str:
    cache = "cached on disk" if HF_CACHE.exists() else "will download from Hub"
    apple = "compiled" if APPLE_BIN.exists() else "missing binary"
    return (
        f"Parakeet `{PARAKEET_ID}`: **{cache}**. "
        f"Apple Speech CLI: **{apple}**. "
        "Record once, then Compare — both engines see the same WAV."
    )


THEME = gr.themes.Soft(
    primary_hue="slate",
    secondary_hue="blue",
    neutral_hue="slate",
)

with gr.Blocks(title="Cadence vs Parakeet") as demo:
    gr.Markdown("# Cadence vs Parakeet")
    status = gr.Markdown(startup_status())
    gr.Markdown(
        "Record a sentence (or upload a clip). Both engines transcribe the **same file**: "
        "macOS 26 `SpeechTranscriber` (what Cadence uses) and NVIDIA Parakeet TDT 0.6b via MLX."
    )
    with gr.Row():
        audio = gr.Audio(
            sources=["microphone", "upload"],
            type="filepath",
            format="wav",
            label="Your recording",
        )
        reference = gr.Textbox(
            label="Optional: what you actually said",
            placeholder="Type the script if you want a true WER, not just agreement between engines.",
            lines=6,
        )
    compare_btn = gr.Button("Compare both engines", variant="primary")
    with gr.Row():
        apple_out = gr.Markdown()
        parakeet_out = gr.Markdown()
    summary = gr.Markdown()
    with gr.Accordion("How Parakeet is loaded from Hugging Face", open=False):
        hf_out = gr.Markdown(
            "Click Compare once. If the model is already in `~/.cache/huggingface`, "
            "`from_pretrained` only reads local files."
        )

    compare_btn.click(
        fn=compare,
        inputs=[audio, reference],
        outputs=[apple_out, parakeet_out, summary, hf_out],
    )

if __name__ == "__main__":
    os.environ.setdefault("PATH", "")
    os.environ["PATH"] = "/opt/homebrew/bin:" + os.environ["PATH"]
    try:
        load_parakeet()
        print(f"parakeet attached in {_parakeet_load_ms:.0f} ms", flush=True)
    except Exception as exc:  # noqa: BLE001
        _parakeet_error = str(exc)
        print(f"parakeet preload failed: {exc}", flush=True)
    demo.launch(
        server_name="127.0.0.1",
        server_port=7860,
        theme=THEME,
        inbrowser=False,
        show_error=True,
    )
