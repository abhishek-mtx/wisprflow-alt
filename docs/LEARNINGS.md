# Production lessons

These are mistakes Cadence already paid for. Read them before changing signing, TCC, the event tap, the HUD, injection, or live speech.

Cadence is local\-only dictation. The microphone hears you. Accessibility types into other apps. None of the lessons below are an excuse to send audio to a Cadence server. There still is not one.

## TCC is bound to the code signature, not the bundle ID

Ad\-hoc signing (`CODE_SIGN_IDENTITY: "-"`) produces a **new cdhash every rebuild**. Accessibility and Input Monitoring grants then silently die. Settings can still show Cadence ON because that row is the previous binary.

Fix: stable self\-signed identity **Cadence Local Dev**, created by `scripts/setup-signing.sh`. `project.yml` sets `CODE_SIGN_STYLE: Manual` and `CODE_SIGN_IDENTITY: "Cadence Local Dev"`.

Inspect what TCC actually keyed:

```bash
codesign -d -r- /Applications/Cadence.app
```

Shape:

```
designated => identifier "com.cadence.dictation" and certificate leaf = H"…"
```

The leaf is the Cadence Local Dev certificate on this Mac. A teammate who ran `setup-signing.sh` gets a different leaf. Do not export that identity. Team installs use Developer ID, not this cert.

Put the app at `/Applications/Cadence.app` so the Privacy row matches the binary people launch. Mixing DerivedData and `/Applications` looks like "permissions are ON but Fn does nothing."

## Hardened Runtime without the microphone entitlement lies

Enabling Hardened Runtime without `com.apple.security.device.audio-input` made System Settings show Microphone **ON** while `AVCaptureDevice.authorizationStatus` stayed `.notDetermined`. Relaunch did not help. The process was not entitled to the device.

Both `WisprFlowAlt.entitlements` and `CompareLab.entitlements` now contain only that key. Do not "fix" mic issues by adding the App Sandbox. Trust the API status, not the Settings toggle. If status is `.denied`, `PermissionService.relaunchApp()` exists because macOS sometimes keeps `.denied` on the live process after the user flips the switch.

## Xcode's debug\-dylib split needs a Team ID

A Team\-ID\-less self\-signed leaf cannot satisfy Xcode's debug dylib (executable and dylib must share a team). The process failed to launch or the debugger refused to load.

Fix already in `project.yml`: `ENABLE_DEBUG_DYLIB: NO`.

`xcodebuild test` injects Apple\-signed `XCTest.framework` into that same host. Hardened Runtime library validation then fails with "different Team IDs" even when both Cadence and the `.xctest` are `Cadence Local Dev` with `TeamIdentifier=not set`. Debug signs with `WisprFlowAlt.debug.entitlements`, which includes `com.apple.security.cs.disable-library-validation`. Release stays audio\-input only. XcodeGen `entitlements.properties` must keep `device.audio-input` or `xcodegen generate` writes an empty plist.

## Never `tccutil reset` from Debug UI

Resetting Accessibility or Input Monitoring **deletes the grant the user just gave**. Fn dies until they find the toggle again. `PermissionService` must not shell out to `tccutil`. Open the Settings pane and prompt with `AXIsProcessTrustedWithOptions` / `CGRequestListenEventAccess`. If the row is stale, the copy tells them to remove Cadence and drag `/Applications/Cadence.app` back in.

## `CGEvent` tap on the main run loop times out and swallows Fn

A listen tap whose callback is slow to return is disabled (`tapDisabledByTimeout`), often dozens of times per session. On the main run loop it competes with SwiftUI, speech, and polish. Fn then vanishes with no UI.

### What the tap does now

* Dedicated thread `com.cadence.hotkey-tap` with its own run loop
* `listenOnly` (a default tap at headInsert can freeze the UI and eat keys)
* Re\-enable on `tapDisabledByTimeout` / `tapDisabledByUserInput`
* 2s watchdog if disable happens with no event
* `NSEvent.addGlobalMonitorForEvents` fallback
* `isPTTDown` so tap \+ monitor do not double\-fire

Hands\-free double\-tap defaults **off**. Fn `flagsChanged` often looks like a double\-tap and left Cadence in hands\-free while the user thought push\-to\-talk was broken.

## `NSPanel.isFloatingPanel = true` resets window level to 3

That is `.floating`. Fullscreen Electron / Cursor sit above it. The Flow Bar disappears.

Set floating **first**, then overlay level `CGWindowLevelForKey(.assistiveTechHighWindow) + 1`. Keep `fullScreenAuxiliary` and `canJoinAllSpaces`. Draw the bar in AppKit (`FlowBarCanvas`), not a SwiftUI window that loses the level war.

## Electron paste

macOS discards synthesized `⌘V` unless the posting process is trusted for Accessibility. Clipboard\-only without AX is "text is on the pasteboard, user pastes." Do not log `Inject OK` in that state.

Do not post `⌘V` twice (pid **and** HID tap). Electron reads the window\-server stream, so HID is preferred when the target is actually frontmost. Otherwise `postToPid`. Track the last **non\-Cadence, non\-system** frontmost app continuously. Capture it **before** the HUD, or Studio becomes the target and paste goes nowhere.

Wait for Fn/Option to clear before sending `⌘V` or you chord the paste.

Terminal and iTerm default to clipboard. Cursor and VS Code are seeded the same way. AX value writes on Electron composers are a last resort.

## SpeechAnalyzer live mic

File STT (Compare's `AppleEngine`, `scripts/apple_speech_transcribe.swift`) is not the product path.

Live path rules:

* `analyzer.start(inputSequence:)` **before** installing the mic tap and yielding buffers
* `AVAudioConverter.primeMethod = .none` or the stream is primed with silence/junk
* Do not reset the audio meter at finalize. Reset on cancel / HUD hide only
* SpeechTranscriber emits revisions of the same utterance. Absorb them (`TranscriptStitcher.absorbRevision` on the file path; volatile replace \+ final segments on the live path). Concatenating every callback duplicates "the the the" hypotheses

`SpeechEngine.cancel()` resets the meter. `stopAndFinalize()` does not. Keep it that way.

## Dictionary: whole\-phrase `\b` matching

Substring replace turns `ai` into a landmine (`said` → `sAId` or worse). `TextNormalizer.applyDictionary` uses `\b` around the escaped phrase, longest phrase first, case\-insensitive unless the entry says otherwise. Seed `CorporateAIDictionary` (v2) for spoken "a i" → `AI`, "push to talk" → `push-to-talk`, and the usual corporate/ASR mishears. Re\-seed is idempotent per phrase.

## Window restoration freezes the chrome

After a crash during restore, AppKit shows a modal "Do you want to try to reopen its windows again?" alert. If that alert is off the active Space, Cadence looks frozen. Close, minimize, and Settings do nothing. The main thread is idle.

Do not set `collectionBehavior` to `moveToActiveSpace` on a SwiftUI `Window`. That combination with `fullScreenNone` throws in `_validateCollectionBehavior:` and aborts.

`CadenceAppDelegate` returns false for restore and save. Studio uses `.restorationBehavior(.disabled)`.

MenuBarExtra can switch the app to accessory activation. Then Studio is visible but never key, clicks fall through, and `kAXWindowsAttribute` is empty. Force `NSApp.setActivationPolicy(.regular)` on launch.

Onboarding keeps a titled window. A hidden title bar made `kAXWindowsAttribute` return the application instead of windows, so Continue and Finish had no AX targets. `openWindow` from the menu extra does not present a Window scene. Call `CadenceWindowSpace.revealOnboarding()` from a real window, the same way Studio is revealed. Do not assign `collectionBehavior`.

Launch presents only the wizard when `settings.hasCompletedOnboarding` is false. Finish opens Studio from the onboarding window. Do not present Studio and Onboarding in the same launch. Skip the MenuBarExtra `Item-0` window. Do not call `setAccessibilityElement(true)` on titled chrome. That made `kAXWindowsAttribute` return the application.

## Related, also true

* Cadence is not sandboxed and not Mac App Store. Team share is a notarized Developer ID DMG. See [DISTRIBUTION.md](DISTRIBUTION.md).
* Do not share Debug DerivedData builds, login\-keychain certs, or TCC databases.
* Compare Lab's Wispr column can upload audio if someone pastes an API key. That is opt\-in comparison, not Cadence dictation.
