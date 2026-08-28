# Cadence

Cadence is on\-device dictation for **macOS 26\+**. Hold Fn, speak, release. Text lands at the caret in the app you were already in, including Electron apps such as Cursor.

Speech stays on this Mac. Apple `SpeechAnalyzer` / `SpeechTranscriber` do the recognition. Optional polish uses Apple Intelligence / Foundation Models on\-device. History is local SwiftData. There is no Cadence cloud STT, no audio upload, and no Cadence account.

Bundle ID: `com.cadence.dictation`.

## Why this exists

Cadence was built as a **local\-only** Wispr Flow alternative. Same global push\-to\-talk habit. Audio does not go to a vendor.

### Wispr Flow

Wispr Flow is a strong product if cloud or vendor STT is acceptable. On healthcare and corporate machines it often is not. Audio leaves the Mac. That is a data\-control problem even when the vendor is reputable. Cadence is the control\-your\-audio alternative. Recognition and optional polish run on\-device. Cadence does not operate a speech cloud and does not create a Cadence account.

### Apple system dictation and per\-app mics

macOS dictation, and the microphone control inside Notes, Slack, Cursor, and similar, is per\-app. It is not global push\-to\-talk. There is no unified overlay, no Cadence\-style custom dictionary, no on\-device polish pipeline like Cadence, and a weaker story for injecting into Electron. Switch apps and you start over. Cadence is a system\-wide dictation injector. One Fn hold, one Flow Bar, paste into whatever was focused.

### What "local" actually means

The microphone hears you. If you grant Accessibility, Cadence can insert text into other apps. That is the product, not a side effect. Cadence is **not** HIPAA certified and does not claim to be. If the rule is "no process on this Mac may hear or type," do not run dictation software.

## What stays on this Mac

| Data | Where it goes |
|:-----|:--------------|
| Microphone audio | On\-device `SpeechAnalyzer` / `SpeechTranscriber` only. Not uploaded to a Cadence server. |
| Optional polish | Apple Intelligence / Foundation Models on\-device, when available. |
| History, dictionary, snippets, styles | Local SwiftData store `WisprFlowAlt`. |
| Debug logs | `~/Library/Logs/Cadence/cadence.debug.log`. Debug builds may include transcript previews. Release builds log counts and errors, not transcript text. |

Compare Lab can send a clip to Wispr Flow **if you paste a Wispr API key**. That is an opt\-in comparison tool. Cadence itself never does that.

## Features

* Global **Fn** push\-to\-talk (listen\-only event tap, so Wispr Flow can share the same key)
* Floating Flow Bar overlay while you talk, including over fullscreen Electron
* Custom dictionary with whole\-phrase matching (so `ai` does not rewrite `said`)
* Optional on\-device polish, per\-app styles, snippets, and transforms
* Clipboard / Accessibility injection aimed at Electron (Cursor, VS Code, Slack)
* Command Mode (`⌘⌃C`) to rewrite selected text from a spoken instruction
* Local history in Settings
* Compare Lab sibling app for side\-by\-side Cadence / Parakeet / Wispr transcripts. Cadence never uploads audio. Compare Lab can call Wispr only if you paste a key.

## Requirements

* macOS 26.0 or later (SpeechAnalyzer / SpeechTranscriber)
* Xcode 26\+
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
* Apple Intelligence is optional. Polish falls back to light cleanup when it is unavailable.

First speech use may download on\-device speech assets. Run once while online if the Mac is usually offline.

## Local Debug build

Ad\-hoc signing (`CODE_SIGN_IDENTITY: "-"`) gives every rebuild a new code directory hash. Accessibility and Input Monitoring then die silently. Debug builds use the stable self\-signed identity **Cadence Local Dev**.

```bash
./scripts/setup-signing.sh
xcodegen generate
open WisprFlowAlt.xcodeproj
```

Scheme **Cadence**, destination **My Mac**. Copy `Cadence.app` to `/Applications` and launch that copy so TCC binds to a stable path. Grant Microphone, Accessibility, and Input Monitoring once. Rebuilds that keep the same identity keep those grants.

Details: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md), [docs/LEARNINGS.md](docs/LEARNINGS.md).

### Shortcuts

| Action | Default |
|:-------|:--------|
| Push\-to\-talk | Hold **Fn** |
| Hands\-free | Off by default. Optional double\-tap Fn in Settings → Hotkeys |
| Command Mode | Hold `⌘⌃C` |
| Cancel | `Esc` |

Presets for Option (`⌥`) and `⌃Space` live in Settings → Hotkeys.

## Permissions

| Permission | Why |
|:-----------|:----|
| Microphone | Capture speech for on\-device transcription |
| Input Monitoring | See Fn (and other hotkeys) while another app is focused |
| Accessibility | Insert or synthesize paste into the target app. Without it, text is copied and you press `⌘V` yourself. |

Cadence is **not** sandboxed. Global event taps and Accessibility injection need the sandbox off. It cannot ship on the Mac App Store. Share a notarized Developer ID DMG, not a Debug copy from DerivedData. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Compare Lab

Sibling target `com.cadence.compare`, Xcode scheme **Compare**, product name Compare.

Hold Fn once. Cadence transcribes live (and skips paste while Compare is in session). Compare also runs local Parakeet (MLX sidecar) and, optionally, Wispr Flow (desktop clipboard or cloud API key). Use it to judge quality. Do not treat the Wispr column as part of Cadence's privacy story.

## Tests

```bash
xcodegen generate
xcodebuild test -scheme Cadence -destination 'platform=macOS'
```

## Docs

* [Architecture](docs/ARCHITECTURE.md)
* [Production lessons](docs/LEARNINGS.md)
* [Distribution and team sharing](docs/DISTRIBUTION.md)
* [Security and privacy](SECURITY.md)
* [Contributing](CONTRIBUTING.md)
* [ADR 0001: local on\-device dictation](docs/adr/0001-local-on-device-dictation.md)
* [ADR 0002: no sandbox, Hardened Runtime](docs/adr/0002-no-sandbox-hardened-runtime.md)
* [ADR 0003: stable local signing for TCC](docs/adr/0003-stable-local-signing-for-tcc.md)
* [ADR 0004: live SpeechAnalyzer](docs/adr/0004-speechanalyzer-live-mic.md)
