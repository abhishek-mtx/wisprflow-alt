# ADR 0001: Local on\-device dictation

## Status

Accepted.

## Context

We needed global push\-to\-talk dictation on macOS that could paste into whatever the user was already typing in, including Electron (Cursor, VS Code, Slack). The users who asked for this sit on healthcare and corporate machines. Sending microphone audio to a vendor STT service is a non\-starter there, even when the vendor is Wispr Flow.

Apple already ships dictation. It is per\-app. It does not give a system\-wide Fn hold, a custom dictionary, a unified overlay, or a reliable inject path into Electron. People lose the session every time they change windows.

Cadence exists so speech stays on this Mac and the rest of the product (hotkey, HUD, dictionary, polish, paste) still feels like a dedicated dictation injector.

## Decision

Build **Cadence** (`com.cadence.dictation`) as a local\-only macOS 26 app.

* Recognition via Apple `SpeechAnalyzer` / `SpeechTranscriber` on\-device. No Cadence cloud STT, no audio upload, no Cadence account.
* Optional polish via Apple Intelligence / Foundation Models on\-device. If the model is missing, light local cleanup only.
* History, dictionary, snippets, styles, and injection profiles in local SwiftData.
* Global Fn push\-to\-talk (listen\-only event tap) and Accessibility / clipboard injection into other apps.

Be explicit in docs and UI: the mic hears you; Accessibility can type into other apps. That is the product. Do not claim HIPAA certification.

## Alternatives considered

### Wispr Flow

Global PTT and a polished overlay already exist there. Typical STT is cloud or vendor\-hosted. Audio leaves the machine. That is exactly the enterprise objection. Cadence is the control\-your\-audio alternative, not a clone of Wispr's backend.

Compare Lab may call Wispr's API **if a user pastes a key**, as a quality benchmark. Cadence's dictation path does not.

### Apple system dictation

Built in, no extra app, on\-device options on Apple Silicon. Per\-app, not a system\-wide injector. No Cadence dictionary / polish / Electron paste pipeline. Users still context\-switch into each app's mic control.

### Per\-app microphone buttons (Cursor, Slack, Notes, …)

Same problem as system dictation, worse UX. No unified Flow Bar. No global Fn. Injection quality is whatever that app implemented.

## Consequences

* **macOS 26\+** is a hard floor (`SpeechTranscriber`).
* App Sandbox stays **off**. Mac App Store distribution is out. Team sharing is Developer ID \+ notarization. See [0002](0002-no-sandbox-hardened-runtime.md).
* Accessibility and Input Monitoring are mandatory for the full product. TCC is signature\-bound. See [0003](0003-stable-local-signing-for-tcc.md).
* Privacy story is "on this Mac," not "certified for a hospital." Docs must not overclaim.
* First launch may download Apple speech assets. Offline\-first machines need one online run.
