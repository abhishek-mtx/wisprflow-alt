# ADR 0004: Live SpeechAnalyzer, not file STT

## Status

Accepted.

## Context

Dictation has to feel like push\-to\-talk: hold Fn, see a live waveform, release, paste. A record\-to\-WAV\-then\-transcribe pipeline adds end latency and kills partials in the HUD.

Apple's macOS 26 API for this is `SpeechAnalyzer` \+ `SpeechTranscriber` with `.progressiveTranscription`. File analysis is a different shape (used in Compare Lab when live Cadence text does not arrive).

## Decision

Cadence's product path is live mic into `SpeechAnalyzer`, not a WAV file.

* `analyzer.start(inputSequence:)` before feeding `AVAudioEngine` tap buffers
* `AVAudioConverter.primeMethod = .none`
* Volatile results replace the in\-flight hypothesis; finals append as segments
* Absorb SpeechTranscriber revisions rather than concatenating duplicates (`TranscriptStitcher` on the file/Compare path)

File STT remains for Compare's Cadence fallback and `scripts/apple_speech_transcribe.swift`. It is not how Fn dictation works.

## Consequences

* macOS 26 is required. There is no Cadence cloud fallback if `SpeechTranscriber` is unavailable.
* Ordering bugs (start vs feed, converter prime, early meter reset) look like "empty transcript" or a dead HUD. See [LEARNINGS.md](../LEARNINGS.md).
* On\-device assets may download on first locale use (`AssetInventory`). Bootstrap calls `SpeechEngine.prepare` so the first PTT is not a download spinner.
