# Security and privacy

Cadence is a local productivity tool. It can hear the microphone. If you allow Accessibility, it can type into other apps. Treat those grants as real.

Cadence is **not** HIPAA certified. On\-device recognition is not the same as a compliance program.

## Local\-only dictation

Cadence (`com.cadence.dictation`) does not run a speech cloud, does not upload audio, and does not create a Cadence account.

| Data | Handling |
|:-----|:---------|
| Microphone audio | Transcribed on this Mac with Apple `SpeechAnalyzer` / `SpeechTranscriber`. |
| Optional rewrite | Apple Intelligence / Foundation Models on\-device when available. Otherwise light local cleanup. |
| History, dictionary, snippets, styles, injection profiles | SwiftData on disk (`WisprFlowAlt`). |
| Release logs | Counts and errors in `~/Library/Logs/Cadence/cadence.debug.log`. Not transcript text. |
| Debug logs | May include short transcript previews. Do not attach them to public issues. |

Compare Lab (`com.cadence.compare`) is a separate app. If you paste a Wispr Flow API key, **that** column uploads the recorded clip to Wispr's API. Cadence's own dictation path never does this.

## Permissions

These are TCC prompts, not sandbox entitlements.

| Permission | Why |
|:-----------|:----|
| Microphone | Capture speech |
| Input Monitoring | Global push\-to\-talk (default **Fn**) while another app is focused |
| Accessibility | Insert text or post synthetic `⌘V`. Without it, Cadence copies the transcript and you paste by hand. |

`PermissionService` treats microphone \+ Input Monitoring as required to listen. Accessibility is required to auto\-insert. Settings can show a toggle ON for an older binary. Trust `AXIsProcessTrusted()` and `AVCaptureDevice.authorizationStatus`, not the Settings row alone.

Compare Lab and Cadence talk over `DistributedNotificationCenter` (`CompareSync`). Cadence posts `com.cadence.dictation.transcriptReady` with the transcript text so Compare can fill its Cadence column. Compare posts `sessionBegan` / `sessionEnded` so Cadence transcribes without inserting. That channel stays on\-machine. It is not an audio upload.

## Entitlements and sandbox

Both Cadence and Compare request only:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

| Build flag | Value | Why |
|:-----------|:------|:----|
| `ENABLE_APP_SANDBOX` | `NO` | Event taps and Accessibility injection do not work in the App Sandbox. |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for Developer ID. Without `audio-input`, Settings can show Microphone ON while the process stays `.notDetermined`. |
| `LSUIElement` | `false` | Cadence is a normal app (Dock \+ menu bar extra), not a faceless agent. |

Do not add sandbox entitlements. Cadence cannot ship on the Mac App Store while the sandbox is off.

Xcode Debug builds also get `com.apple.security.get-task-allow`. That is the debugger, not the entitlements file. Release archives from `scripts/notarize.sh` should not include it.

## Signing

TCC binds Accessibility and Input Monitoring to the **code signature**, not the bundle ID alone.

* Local Debug: self\-signed identity `Cadence Local Dev` (`scripts/setup-signing.sh`). Same leaf → grants survive rebuilds.
* Team install: notarized Developer ID Application. Not an ad\-hoc DerivedData copy.

Do not share login keychain certs, `.p12` files, notary passwords, or TCC databases. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) and [docs/LEARNINGS.md](docs/LEARNINGS.md).

## Reporting issues

Message the maintainer or open a private issue. Do not attach Debug logs if they may contain transcript previews. Do not paste API keys, notary credentials, or signing material.
