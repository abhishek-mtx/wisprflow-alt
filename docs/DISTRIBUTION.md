# Distribution

Cadence is local\-only dictation. Share the app, not audio, not signing keys, not TCC databases.

Cadence cannot ship on the Mac App Store. The App Sandbox is off (`ENABLE_APP_SANDBOX: NO`) so global `CGEvent` taps and Accessibility paste work. The supported team install is a **notarized Developer ID DMG**.

## What the team must grant

Install to `/Applications/Cadence.app`, launch that copy, then grant:

| Permission | Required to | If missing |
|:-----------|:------------|:-----------|
| Microphone | Capture speech | Settings may lie unless `com.apple.security.device.audio-input` is present. Check `AVCaptureDevice.authorizationStatus`. |
| Input Monitoring | Hold **Fn** while another app is focused | Push\-to\-talk never fires. |
| Accessibility | Auto\-insert / synthetic `⌘V` into Cursor and other apps | Transcript is copied. User pastes with `⌘V`. |

Accessibility inserting into other apps is the product. Microphone hearing speech is the product. Cadence is not HIPAA certified.

First launch may download on\-device speech models. Offline machines should run once online.

## Local Debug (developers)

TCC keys Accessibility / Input Monitoring to the **code signature**. Ad\-hoc signing (`CODE_SIGN_IDENTITY: "-"`) produces a new cdhash every rebuild, so grants die even when Settings still shows ON.

1. Once per machine, create the stable identity: `./scripts/setup-signing.sh` (imports **Cadence Local Dev** into the login keychain).
2. `xcodegen generate` and open `WisprFlowAlt.xcodeproj`.
3. Scheme **Cadence** → destination **My Mac**. `project.yml` already sets `CODE_SIGN_IDENTITY` to `Cadence Local Dev`, `ENABLE_HARDENED_RUNTIME: YES`, `ENABLE_DEBUG_DYLIB: NO`.
4. Put the app at `/Applications/Cadence.app` (Xcode Run is fine if you always launch the same signed binary).
5. Grant Microphone, Accessibility, and Input Monitoring **once**. Rebuilds with the same leaf keep those grants.

Inspect the designated requirement:

```bash
codesign -d -r- /Applications/Cadence.app
```

Expect `identifier "com.cadence.dictation" and certificate leaf = H"…"`. The hash is **this machine's** Cadence Local Dev leaf. A teammate who ran `setup-signing.sh` has a different hash. That is expected. Do not export and share the identity.

Never `tccutil reset` Accessibility or Input Monitoring from a Debug UI. It deletes the grant you just gave.

## Team share (everyone else)

**Do not** AirDrop a Debug build from DerivedData. Gatekeeper will fight it, and TCC will not stay bound across rebuilds.

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) (personal team is enough).
2. In Xcode, create a **Developer ID Application** certificate for that team.
3. Store notary credentials once on the machine that builds:

```bash
xcrun notarytool store-credentials CadenceNotary \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password APP_SPECIFIC_PASSWORD
```

4. Build, notarize, staple, wrap:

```bash
export TEAM_ID=YOUR_TEAM_ID
./scripts/notarize.sh
```

5. Share **`build/Cadence.dmg`** only. Teammates open the DMG, drag Cadence to Applications, launch, and grant the three permissions above.

`scripts/notarize.sh` archives the **Cadence** scheme as Release, exports Developer ID, submits with profile `CadenceNotary` (or `APPLE_ID` \+ `APP_SPECIFIC_PASSWORD`), staples, then writes `build/Cadence.dmg`. It needs full Xcode, not Command Line Tools only.

## Packaging facts (must match `project.yml`)

| Setting | Value |
|:--------|:------|
| Bundle ID | `com.cadence.dictation` |
| Compare Lab | `com.cadence.compare`, scheme **Compare** |
| Sandbox | Off |
| Hardened Runtime | On |
| Entitlements | `com.apple.security.device.audio-input` only (`WisprFlowAlt.entitlements`, `CompareLab.entitlements`) |
| `LSUIElement` | `false` |
| Default push\-to\-talk | Fn (key code 63) |

Accessibility and Input Monitoring are **not** entitlements. They are TCC.

## Per\-app injection

Defaults seed Terminal, iTerm2, Cursor, and VS Code toward **clipboard** paste. Electron often ignores AX value writes. Add more under Settings → Injection when a specific app fails.

`KeyShortcut.conflictsWithSystem()` rejects bare letter keys, reserved combos (`⌘Q`, `⌘W`, …), and identical PTT / Command Mode bindings.

## Do not share

* Login keychain certs or a `.p12` of Cadence Local Dev / Developer ID
* Notary app\-specific passwords or `notarytool` profiles
* `TCC.db` or screenshots of another person's Privacy settings as a "fix"
* Debug logs from a Debug build (they can include transcript previews)
* Ad\-hoc or DerivedData copies as the official team app
