# ADR 0002: No sandbox, Hardened Runtime, audio\-input entitlement

## Status

Accepted.

## Context

Cadence must install a session `CGEvent` tap (global Fn) and use Accessibility to paste into other apps. The Mac App Store requires the App Sandbox. The sandbox blocks this product.

Developer ID distribution wants Hardened Runtime. Turning that on without `com.apple.security.device.audio-input` made Settings show Microphone ON while `AVCaptureDevice.authorizationStatus` stayed `.notDetermined`.

## Decision

* `ENABLE_APP_SANDBOX: NO` for Cadence and Compare Lab.
* `ENABLE_HARDENED_RUNTIME: YES`.
* Entitlements files contain **only** `com.apple.security.device.audio-input`.
* Accessibility and Input Monitoring remain TCC prompts, not entitlements.
* Ship to the team as a notarized Developer ID DMG (`scripts/notarize.sh`). Do not ship Debug / ad\-hoc copies. Do not target the Mac App Store.

## Consequences

* Notarization and a paid Developer ID cert are required for anyone who is not the local developer.
* Entitlement surface stays small on purpose. Do not "add sandbox later" without dropping global tap \+ AX inject.
* Hardened Runtime without `audio-input` will look like a TCC bug. It is not. See [LEARNINGS.md](../LEARNINGS.md).
