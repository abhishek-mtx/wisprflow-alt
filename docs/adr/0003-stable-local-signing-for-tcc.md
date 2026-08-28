# ADR 0003: Stable local signing for TCC

## Status

Accepted.

## Context

macOS TCC binds Accessibility and Input Monitoring to the app's **code signature**. Ad\-hoc signing (`CODE_SIGN_IDENTITY: "-"`) changes the cdhash on every Xcode build. Grants vanish. Settings still shows the old row as ON. Fn and auto\-paste look randomly broken.

Xcode's debug\-dylib split also refuses to load when the executable and the dylib have no Team ID, which a self\-signed leaf cannot provide.

## Decision

* Local Debug uses a stable self\-signed identity **Cadence Local Dev** (`scripts/setup-signing.sh`).
* `project.yml`: `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Cadence Local Dev"`, `DEVELOPMENT_TEAM: ""`, `ENABLE_DEBUG_DYLIB: NO`.
* Developers grant Mic / AX / Input Monitoring once against `/Applications/Cadence.app` (or one stable signed copy).
* Team installs use Developer ID, not this identity. Do not share the login keychain cert or a `.p12`.
* Debug UI must never `tccutil reset` those services.

Designated requirement shape: `identifier "com.cadence.dictation" and certificate leaf = H"…"`. The leaf is the Cadence Local Dev certificate on this Mac. Other machines differ.

## Consequences

* First clone needs `./scripts/setup-signing.sh` before a useful Debug run.
* Each developer has their own leaf. TCC does not travel with the repo.
* Release signing in `scripts/notarize.sh` overrides to `CODE_SIGN_STYLE=Automatic` \+ `DEVELOPMENT_TEAM`. That is intentional.
