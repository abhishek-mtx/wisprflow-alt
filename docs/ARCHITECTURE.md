# Architecture

Cadence is a local\-only macOS 26 dictation injector. Hold Fn, capture audio, transcribe on\-device, polish on\-device, paste into the last real app. Nothing in the dictation path talks to a Cadence server.

Compare Lab (`com.cadence.compare`) is a sibling target that can call Wispr's cloud API **if the user pastes a key**. That is not Cadence's runtime.

## Layers

`AppModel` is the composition root. It owns SwiftData, wires services, seeds defaults, and starts the hotkey tap.

| Layer | Types | Role |
|:------|:------|:-----|
| App | `WisprFlowAltApp`, `AppModel`, `AppSettings`, `CadenceStudioView`, `MenuBarView`, `OnboardingView` | Windows, menu bar extra, settings, UserDefaults |
| Dictation | `DictationSessionController`, `CommandModeController` | Session state machines (record → finalize → polish → inject, or rewrite selection) |
| Speech | `SpeechEngine`, `AudioCaptureSession`, `AnalyzerBufferConverter` | Live `SpeechAnalyzer` \+ `SpeechTranscriber` (`.progressiveTranscription`) |
| Hotkeys | `GlobalHotkeyService`, `KeyShortcut` | Listen\-only `CGEvent` tap \+ `NSEvent` fallback |
| Injection | `TextInjectionService`, `InjectionProfile` | Remember target app; AX / clipboard / key\-event insert |
| Permissions | `PermissionService` | Mic, Accessibility, Input Monitoring; never `tccutil reset` |
| HUD | `OverlayHUDController`, `FlowBarCanvas` | AppKit `NSPanel` Flow Bar over Electron |
| Polish | `PostProcessPipeline`, `FoundationModelsPolish`, `TextNormalizer` | Dictionary, snippets, Apple Intelligence, transforms |
| Models | `DataModels`, `SeedData`, `CorporateAIDictionary`, `StatsStore` | SwiftData \+ corporate/AI seed dictionary |
| Shared | `CompareSync`, `TranscriptStitcher`, `DictationPolish` | Cadence ↔ Compare notifications; revision stitching |
| Compare Lab | `CompareSession`, `AppleEngine`, `ParakeetEngine`, `WisprEngine`, `ClipRecorder`, `FnHoldMonitor` | Side\-by\-side quality tool |

## Data flow (push\-to\-talk)

1. User holds **Fn** (default `KeyShortcut.defaultPushToTalk`, key code 63).
2. `GlobalHotkeyService` sees `flagsChanged` on a dedicated tap thread (or the `NSEvent` fallback). It posts `cadencePushToTalkBegan` without swallowing the key, so Wispr Flow can bind Fn too.
3. `DictationSessionController.beginPushToTalk()` calls `TextInjectionService.rememberTargetApp()` **before** the HUD appears, so Studio or the Flow Bar does not become the paste target.
4. If Settings → HUD is on, `OverlayHUDController` shows the Flow Bar.
5. `SpeechEngine.start` builds `SpeechTranscriber`, then `try await analyzer.start(inputSequence:)`, **then** starts `AVAudioEngine` and attaches the converter. `AVAudioConverter.primeMethod = .none`.
6. Volatile results replace the in\-flight guess. Final segments append. The HUD pumps `partialTranscript`.
7. User releases Fn → `stopAndFinalize()` (`finalizeAndFinishThroughEndOfInput`, wait until the transcript is stable).
8. `PostProcessPipeline.run`: `TextNormalizer.normalize` (spoken "comma" / "period"), whole\-phrase dictionary, snippets, optional `FoundationModelsPolish`, then any per\-app `TransformRule`.
9. If Compare posted `sessionBegan`, Cadence skips insert and publishes the text via `CompareSync`.
10. Otherwise `TextInjectionService.insert` runs. Accessibility must be trusted or Cadence copies to the pasteboard and tells the user to press `⌘V`. Electron\-like bundle IDs prefer clipboard paste, one `⌘V` path, not pid \+ HID together.
11. A `TranscriptRecord` is stored in SwiftData. `StatsStore` counts words.

Cancel (`Esc`) tears down speech and hides the HUD without injecting.

Command Mode (`⌘⌃C`) captures selected text (or the last transcript), records a spoken instruction, asks Foundation Models to rewrite, and inserts with `replaceSelection: true`.

## Speech

Live dictation does **not** write a WAV and run file STT. That path exists in Compare (`AppleEngine`) and `scripts/apple_speech_transcribe.swift` as a fallback and a CLI.

### Live path details

* `SpeechTranscriber.isAvailable` is a hard gate (macOS 26).
* `AssetInventory` may download locale assets on first use. `SpeechEngine.prepare` warms them at bootstrap so the first Fn is not a download.
* Analyzer starts before mic buffers. Feeding first drops audio or races the stream.
* `primeMethod = .none` or the converter introduces junk at the head of the stream.
* Do not reset `AudioMeterStore` until the session actually ends. `cancel()` and `hud.hide()` reset. Finalize does not reset early, or the Flow Bar dies while you are still talking.
* Compare's file engine uses `TranscriptStitcher.absorbRevision` so growing hypotheses are not concatenated into duplicates.

Dictionary entries are loaded when a take starts (`SpeechEngine.setCustomDictionaryPhrases`). The live transcriber does not currently consume that list. Replacements still run in `PostProcessPipeline` via whole\-phrase `\b` matching in `TextNormalizer`, and polish receives the written forms as spelling hints.

## Hotkeys

`GlobalHotkeyService` creates a session tap, `listenOnly`, `headInsertEventTap`, on thread `com.cadence.hotkey-tap`. The main run loop lost the tap to `tapDisabledByTimeout` (SwiftUI \+ speech \+ polish). A 2s watchdog re\-enables a dead tap. `NSEvent.addGlobalMonitorForEvents` is the backup. `isPTTDown` de\-duplicates when both fire.

Double\-tap hands\-free defaults **off**. Fn `flagsChanged` often looks like a double\-tap and left people stuck in hands\-free while they thought PTT was broken.

## Injection

`TextInjectionService` tracks the last non\-Cadence, non\-system frontmost app (`NSWorkspace.didActivateApplicationNotification`). Ignored: Notification Center, loginwindow, Spotlight, Dock, Finder, WebKit helpers, Cadence, Compare.

Without `AXIsProcessTrusted()`, synthetic `⌘V` is discarded. Cadence must not log "Inject OK" in that state. It copies the text and returns `.failed`.

With Accessibility, auto order is clipboard → accessibility → key events (Electron still prefers clipboard). `postCommandV` posts **either** the HID tap (when the target is frontmost, which Electron actually reads) **or** `postToPid`, never both.

Wait for leftover modifiers after releasing Fn so Option/Fn does not turn `⌘V` into a chord.

## Window and HUD

`LSUIElement` is `false`. Cadence has a Dock icon, a Studio window (`CadenceStudioView`), a menu bar extra, Settings (tabs: General, Hotkeys, Dictionary, Styles, Snippets, Transforms, History, Injection), and an onboarding window.

The Flow Bar is a borderless nonactivating `NSPanel`, mouse\-transparent, `canJoinAllSpaces` \+ `fullScreenAuxiliary`. Set `isFloatingPanel = true` first, then raise the level to `assistiveTechHighWindow` plus one. `isFloatingPanel` resets the level to 3 (`.floating`), which sits under fullscreen Electron.

## Permissions model

| Check | API | Required for |
|:------|:----|:-------------|
| Microphone | `AVCaptureDevice.authorizationStatus(for: .audio)` | Recording |
| Input Monitoring | `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` | Global Fn |
| Accessibility | `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions` | Auto\-insert |

`allRequiredGranted` is mic **and** Input Monitoring. You can listen without Accessibility. You cannot auto\-paste without it.

TCC is bound to the code signature. See [LEARNINGS.md](LEARNINGS.md) and [DISTRIBUTION.md](DISTRIBUTION.md). Hardened Runtime without `com.apple.security.device.audio-input` made Settings show Microphone ON while status stayed `.notDetermined`.

## SwiftData

Schema owned by `AppModel`:

| Model | Purpose |
|:------|:--------|
| `DictionaryEntry` | Spoken phrase → written form |
| `StyleProfile` / `AppStyleMapping` | Per\-app polish prompt (Casual / Formal / Technical defaults) |
| `SnippetEntry` | Trigger → expansion |
| `TransformRule` | Per\-app title case / upper / lower / trim |
| `TranscriptRecord` | Raw \+ polished history |
| `InjectionProfile` | Per\-bundle insert strategy |

`SeedData.ensureDefaults` installs styles, Terminal/iTerm/Cursor/VS Code injection profiles, and `CorporateAIDictionary` (seed version 2, idempotent per phrase).

Settings (`AppSettings`) live in UserDefaults: polish on by default, inject polished text, HUD on, locale, PTT (migrated to Fn), Command Mode, hands\-free off.

## Polish

If Apple Intelligence is available, `LanguageModelSession` cleans filler, punctuation, and mid\-sentence corrections. It is instructed not to invent periods before "I" or after "and/or/but". Dictionary replacements are passed as preferred spellings.

If the model is unavailable, `SpokenTextCleanup.minimal` strips uh/um and obvious repeats. It does not invent sentence breaks at capital letters.

Polish is optional (`settings.polishEnabled`). History still stores raw and polished.

## Compare Lab

`CompareSession` records one WAV (`ClipRecorder`), posts `CompareSync.sessionBegan` so Cadence transcribes without injecting, and fills three columns:

* Cadence: live transcript via distributed notification, else `AppleEngine` file STT
* Parakeet: local `mlx-community/parakeet-tdt-0.6b-v2` sidecar (`scripts/.venv-parakeet`)
* Wispr Flow: desktop clipboard, or REST upload if `WISPR_FLOW_API_KEY` / UserDefaults key is set

File STT and the Wispr column stay in Compare Lab. They are not on Cadence's paste path. That last column is cloud. Keep it out of Cadence's local\-only claim.
