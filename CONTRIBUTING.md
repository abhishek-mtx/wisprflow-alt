# Contributing

Cadence is local\-only dictation. Do not add a cloud STT path, an audio upload, or a Cadence account.

## Build

```bash
./scripts/setup-signing.sh
xcodegen generate
open WisprFlowAlt.xcodeproj
```

Scheme **Cadence**, destination **My Mac**. Target name is still `WisprFlowAlt`; the product is Cadence (`com.cadence.dictation`). Compare Lab is a sibling quality tool on scheme **Compare** (`com.cadence.compare`). It is not the product dictation path.

`project.yml` is the source of truth. After you change it, run `xcodegen generate` again.

Install the Debug app at `/Applications/Cadence.app` so TCC binds to a stable path. Grant Microphone, Accessibility, and Input Monitoring once. Rebuilds that keep **Cadence Local Dev** keep those grants.

## Do not

* `tccutil reset` Accessibility or Input Monitoring. It deletes the grant the user just gave.
* Switch Debug back to ad\-hoc signing (`CODE_SIGN_IDENTITY: "-"`). Grants will die every rebuild.
* Enable `ENABLE_DEBUG_DYLIB`. The local cert has no Team ID.
* Commit `DerivedData`, `.p12`, `.pem`, `.env`, notary passwords, or `~/Library/Logs/Cadence` logs.
* Share a Debug DerivedData build as the team install. Use a notarized DMG. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
* Log "Inject OK" unless `AXIsProcessTrusted()` is true.

## Tests

```bash
xcodegen generate
xcodebuild test -scheme Cadence -destination 'platform=macOS'
```

Read [docs/LEARNINGS.md](docs/LEARNINGS.md) before touching signing, the event tap, the Flow Bar, injection, or `SpeechEngine`.
