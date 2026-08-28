# Cadence first-commit and Studio recent-takes plan

Clean the repo so a private GitHub first commit does not leak this machine. Fence Compare Lab so Cadence still reads as local-only. Put the last five takes on the Studio window as a short list, not a second History page. Cadence users keep a small window. The next engineer inherits one SwiftData query and no parallel take cache. PRs in order are PR-clean, PR-docs, then PR-recent.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-stack.md`. The operator lands the Graphite stack. PR-clean and PR-docs stop at merge-ready for her review of copy. PR-recent is review-gated with screenshots and a video.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on her explicit go.
- [ ] On her go, arm a `/goal` with this exact text. "Run docs/plan.md. PR ids PR-clean, PR-docs, PR-recent. Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Operator lands the stack. Done when Studio shows five recent takes, Compare Lab is fenced in the README, and git add -A would not stage this Mac's home path."
- [ ] Read these from trunk at program start. Re-read them at every tick.
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/autopilot-stack.md`
  - [ ] `git show origin/main:pstack/skills/swarm/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/opening-a-pr.md`
  - [ ] `git show origin/main:pstack/skills/how/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/architect/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/technical-writing/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/unslop/SKILL.md`
- [x] Arm the 30-minute audit tick. In a local session, a real terminal `/loop`. Evidence `scripts/verify-plan-done.sh` plus the local `AGENT_LOOP_TICK_cadence_plan` sleeper. Cloud sleeper is N/A on this Mac.
- [ ] Use this tick prompt, verbatim. "Re-read the execution playbook from trunk and the armed /goal. Audit the operation against both and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then send the operator a status message, whether or not anything changed, with the queue table of PR, owner, state, and head SHA, the verdicts since the last tick, what merged, open operator gates, and blockers."
- [ ] On the operator's hold or stand-down, send every owner a zero-writes order at once.
- [ ] Operator names the LICENSE file text before PR-clean merge. Do not invent a company license.

### Spawn owners

- [ ] Spawn one owner per PR with the full lifecycle the execution playbook names.
- [ ] Follow this dependency graph. Start dependent work only after its parent merges, or base it on the parent branch when the execution playbook stacks.
  - [ ] PR-clean and PR-docs are independent and first. Both branch from `main`.
  - [ ] PR-recent after PR-clean.
- [ ] Hold the file boundaries. PR-clean touches only `CompareLab/ParakeetEngine.swift`, `brand/`, `WisprFlowAlt/Features/Onboarding/`, `WisprFlowAlt/Features/Settings/HotkeySettingsView.swift`, `WisprFlowAlt/Features/Settings/GeneralSettingsView.swift`, `WisprFlowAlt/Services/Injection/TextInjectionService.swift`, `project.yml`, `WisprFlowAlt.xcodeproj/`, and `LICENSE` if the operator supplied one. PR-docs touches only `README.md`, `SECURITY.md`, `docs/`, and `CONTRIBUTING.md`. PR-recent touches only `WisprFlowAlt/Features/Dictation/CadenceStudioView.swift`, a new `WisprFlowAlt/Features/Dictation/RecentTakesStrip.swift`, `WisprFlowAltTests/`, and `WisprFlowAlt/App/CadenceBrand.swift` if tokens are required.
- [ ] Hold the review gate. PR-recent changes an interaction. It waits for the operator's review in chat with screenshots and a video before merge.

### PR mechanics, for every PR

- [x] Open the PR ready, never draft. GitHub `gh` is not logged in on this Mac. Opened Origin PRs with `origin pr create --status open`. PR-clean https://cursor.com/codebase/mtx-group-inc/wisprflow-alt/pull/1 head `d7353e4`. PR-docs https://cursor.com/codebase/mtx-group-inc/wisprflow-alt/pull/2 head `6f648ee`. PR-recent https://cursor.com/codebase/mtx-group-inc/wisprflow-alt/pull/3 head `34f0805`, base `pr-clean`.
- [ ] Run the repo's lint and typecheck once before the PR-facing push. Push with hooks on.
- [ ] Run `/deslop` before each commit and `/no-comments` before review.
- [ ] Triage every Bugbot and security-reviewer comment per `../references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before babysit and again before the merge-ready report.

### Verdict and merge, for every PR

- [ ] At the merge-ready head SHA, run the swarm per `pstack/skills/swarm/SKILL.md`. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. One audit lane that reads the diff and the receipts and distrusts the PR body.
- [ ] Clean only when every lane is `PASS`. Findings go back to the owner. A new head gets a fresh swarm and a fresh verdict.
- [ ] Root appends the PR to the Graphite stack. The operator lands it. After restack, compare `git patch-id` at the verdict SHA to the new head. Drift goes back through swarm.

### Boot recipe, for every live lane

Each live lane runs on its own cloud VM at the PR head. Drive through screenshots of Cadence.app. There is no `control-ui` for this AppKit surface. See Appendix C.

- [ ] `git fetch origin <head-branch> && git checkout <head SHA>`.
- [ ] Run `xcodegen generate` then `xcodebuild -project WisprFlowAlt.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath DerivedData build`. Copy `Cadence.app` to `/tmp/swarm-cadence/Cadence.app`. Launch that copy. Wait until `~/Library/Logs/Cadence/cadence.debug.log` contains `Bootstrap complete`.
- [ ] Do not type into Cadence through CDP Input. Use `screencapture` and log reads as the diagnostics.
- [ ] Save every screenshot to `/tmp/swarm-<pr-id>/worker-<n>/<slug>.png` and return the paths with the report.

## Remove first-commit leaks (PR-clean)

**Depends on.** None.

**Files.**

- [x] Edit `CompareLab/ParakeetEngine.swift`.
- [x] Edit `brand/brand-board.html`.
- [x] Edit `WisprFlowAlt/Features/Onboarding/OnboardingView.swift`.
- [x] Edit `WisprFlowAlt/Features/Settings/HotkeySettingsView.swift`.
- [x] Edit `WisprFlowAlt/Features/Settings/GeneralSettingsView.swift`.
- [x] Edit `WisprFlowAlt/Services/Injection/TextInjectionService.swift`.
- [x] Edit `WisprFlowAlt.xcodeproj/project.pbxproj` by running `xcodegen generate`.
- [ ] Create `LICENSE` only when the operator pastes the chosen text.

**Build.**

- [x] Resolve the Parakeet sidecar from `Bundle.main` then a path relative to the repo root. Delete the string `Documents/Projects/WisprFlow Alt`.
- [x] Change brand-board copy from hold Option to hold Fn.
- [x] Change onboarding finish copy so double-tap hands-free is optional and off by default.
- [x] Call `appModel.applyHotkeySettings()` from the Hotkeys hands-free toggle.
- [x] Show Input Monitoring as granted only when `inputMonitoringTrusted` is true. Drop `|| hotkeys.isRunning`.
- [x] Replace "click into Cursor first" with "click into the app you want to paste into". Keep the Cursor bundle only as one of several last-resort running-app lookups, not the error string.
- [x] Run `xcodegen generate` so CompareLab resources match `project.yml`.

**You see.**

- [x] `rg "Documents/Projects/WisprFlow Alt" CompareLab` prints nothing.
- [x] `rg "Hold ⌥" brand/brand-board.html` prints nothing.
- [x] Log line after toggling hands-free includes `Hotkeys configured`. Evidence `docs/media/PR-clean-hotkeys-toggle.txt`.
- [x] A clone without this user's home folder still builds Cadence. Evidence `docs/media/PR-clean-clone-build.txt`. `/tmp/cadence-nopath-clone` ** BUILD SUCCEEDED **, binary has no home path.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [x] `WisprFlowAltTests` still pass. Run `xcodebuild test -project WisprFlowAlt.xcodeproj -scheme Cadence -destination "platform=macOS"`. **TEST SUCCEEDED** 2026\-08\-28. Debug entitlements include `disable-library-validation` so XCTest can load into Cadence Local Dev.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.6-fast-xhigh` at the PR head, per the boot recipe.

- [x] Lane 1. Open brand-board in a browser. Save `brand-fn.png`. Pass when the visible shortcut is Fn. Evidence `docs/media/PR-clean-brand-fn.png`.
- [x] Lane 2. Open onboarding to the last step. Save `onboarding-handsfree.png`. Pass when the text says double-tap is optional and off by default. Evidence `docs/media/PR-clean-onboarding-handsfree.txt` (AX). Screen Recording TCC blocked PNG.
- [x] Lane 3. Toggle hands-free in Settings, Hotkeys. Save `hotkeys-toggle.png`. Pass when `cadence.debug.log` has a new `Hotkeys configured` line after the click. Evidence `docs/media/PR-clean-hotkeys-toggle.txt`.
- [x] Lane 4. Settings, Permissions with Input Monitoring denied and tap running. Save `input-monitoring-row.png`. Pass when the row is not a green check. Evidence `docs/media/PR-clean-im-denied-probe.txt`. CadenceProbe `hotkeysRunning=true input=false`. AX shows the denied help string. Screen Recording TCC blocked PNG.
- [ ] Lane 5. Trigger inject with no target app. Save `inject-copy.png`. Pass when the HUD or error does not say Cursor as the only app.
- [x] Lane 6. `xcodegen generate` then diff `project.pbxproj` for `parakeet_sidecar.py`. Save `pbxproj-sidecar.png`. Pass when the sidecar is a CompareLab resource. Evidence `docs/media/PR-clean-pbxproj-sidecar.txt`.
- [x] Lane 7. Build Cadence Debug. Save `cadence-build.png`. Pass when `BUILD SUCCEEDED`. Evidence `docs/media/PR-clean-cadence-build.txt`.
- [x] Lane 8. Build Compare Debug. Save `compare-build.png`. Pass when `BUILD SUCCEEDED`. Evidence `docs/media/PR-clean-compare-build.txt`.
- [x] Lane 9. `git grep -n "Documents/Projects"`. Save `no-home-path.png`. Pass when the command is empty. Repo is unborn so `git grep` is empty. `git add -An` also has no `/Users/` paths. Evidence `docs/media/PR-clean-receipts.txt`.
- [x] Lane 10. Confirm `.sf`, `DerivedData`, and `scripts/.venv-parakeet` stay untracked. Save `git-status-ignored.png`. Pass when `git status --ignored` still lists those trees as ignored and not staged. Evidence `docs/media/PR-clean-git-status-ignored.txt`.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Debug build wall time of the Cadence scheme. Head real 7.81s. Trunk has no Cadence scheme. Evidence `docs/media/PR-clean-perf-vs-trunk.txt`.
- [ ] Probe. `/usr/bin/time -p xcodebuild -project WisprFlowAlt.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath DerivedData build` at trunk and at the head, interleaved. Trunk `origin/main` has no `WisprFlowAlt.xcodeproj`.
- [ ] Baseline. Record the trunk real seconds first. Missing.
- [ ] Rule. Head real seconds must be at most trunk times 1.15. Fail if head is slower than that. Cannot apply. Do not check.

**Review gate.** None. PR-clean is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] Root appends the PR to the Graphite stack. The operator lands it.

## Fence Compare Lab in the docs (PR-docs)

**Depends on.** None.

**Files.**

- [x] Edit `README.md`.
- [x] Edit `SECURITY.md`.
- [x] Edit `docs/ARCHITECTURE.md`.
- [x] Edit `docs/LEARNINGS.md`.
- [x] Edit `docs/adr/0003-stable-local-signing-for-tcc.md`.
- [x] Edit `CONTRIBUTING.md`.

**Build.**

- [x] Put one fence paragraph at the top of the README Features Compare bullet. Cadence never uploads audio. Compare Lab can call Wispr only if the user pastes a key.
- [x] Document `CompareSync` on `DistributedNotificationCenter` in `SECURITY.md`. Name `com.cadence.dictation.transcriptReady`.
- [x] Replace the machine cert leaf hash in LEARNINGS and ADR 0003 with "the leaf of Cadence Local Dev on this Mac".
- [x] State in CONTRIBUTING that Compare Lab is a sibling quality tool, not the product path.

**You see.**

- [x] README search for `platform-api.wisprflow` or Wispr key names Compare Lab, not Cadence dictation.
- [x] `rg` for the Cadence Local Dev leaf hash under `docs/` prints nothing outside this plan's live-lane wording. LEARNINGS and ADR 0003 use "the leaf of Cadence Local Dev on this Mac".

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [x] No code tests. Run `true` and record that this PR is docs only.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.6-fast-xhigh` at the PR head, per the boot recipe.

- [x] Lane 1. Open README Why this exists. Save `readme-local.png`. Pass when Cadence is described as on-device with no Cadence cloud STT. Evidence `docs/media/PR-docs-readme-local.png`.
- [x] Lane 2. Open README Features Compare bullet. Save `readme-compare-fence.png`. Pass when Wispr upload is named as Compare Lab only. Evidence `docs/media/PR-docs-readme-compare-fence.png`.
- [x] Lane 3. Open SECURITY.md permissions table. Save `security-ax.png`. Pass when Accessibility is described as insert into other apps. Evidence `docs/media/PR-docs-security.png`.
- [x] Lane 4. Open SECURITY.md after the table. Save `security-comparesync.png`. Pass when `transcriptReady` is named. Evidence `docs/media/PR-docs-security-comparesync.png`.
- [x] Lane 5. Open LEARNINGS TCC section. Save `learnings-no-hash.png`. Pass when the Cadence Local Dev leaf hash is not visible. Evidence `docs/media/PR-docs-learnings-no-hash.png`.
- [x] Lane 6. Open ADR 0003. Save `adr0003-no-hash.png`. Pass when the Cadence Local Dev leaf hash is not visible. Evidence `docs/media/PR-docs-adr0003-no-hash.png`.
- [x] Lane 7. Open CONTRIBUTING local run. Save `contributing-compare.png`. Pass when Compare is labeled a sibling tool. Evidence `docs/media/PR-docs-contributing-compare.png`.
- [x] Lane 8. Open ARCHITECTURE Compare section. Save `arch-compare.png`. Pass when file STT and Wispr stay off the Cadence paste path. Evidence `docs/media/PR-docs-arch-compare.png`.
- [x] Lane 9. `rg -n "HIPAA" README.md SECURITY.md docs`. Save `hipaa-disclaim.png`. Pass when every hit is a not-certified line. Evidence `docs/media/PR-docs-hipaa-and-perf.txt`.
- [x] Lane 10. Render README in GitHub preview or `glow`. Save `readme-preview.png`. Pass when the first screen still leads with local-only Cadence. Evidence `docs/media/PR-docs-readme-preview.png`.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. README byte size. Head 6182. Trunk README absent. Evidence `docs/media/PR-docs-perf-readme-wc.txt`.
- [ ] Probe. `wc -c README.md` at trunk and at the head, interleaved. `git show origin/main:README.md` fails.
- [ ] Baseline. Record the trunk byte count first. Missing.
- [ ] Rule. Head may grow by at most 4000 bytes. Fail if the fence adds a second essay. 6182 vs 0 would fail the rule. Do not check by treating empty trunk as a free 4000.

**Review gate.** None. PR-docs is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] Root appends the PR to the Graphite stack. The operator lands it.

## Show five recent takes on Studio (PR-recent)

**Depends on.** PR-clean.

**Files.**

- [x] Create `WisprFlowAlt/Features/Dictation/RecentTakesStrip.swift`.
- [x] Edit `WisprFlowAlt/Features/Dictation/CadenceStudioView.swift`.
- [x] Edit `WisprFlowAltTests/TextNormalizerTests.swift` or add `WisprFlowAltTests/RecentTakesStripTests.swift` for the prefix-5 helper if it is extracted.
- [x] Do not edit `HistoryView.swift` except to keep Settings History as the full list.

**Build.**

- [x] Add `RecentTakesStrip` that `@Query`s `TranscriptRecord` sorted by `createdAt` reverse and displays `prefix(5)` only.
- [x] Replace the 88-point last-dictation body with a live line while recording or busy, then the five-row strip when idle.
- [x] Keep each row to one line. Show time, clipped `polishedText`, and a copy control. Full text is the VoiceOver label.
- [x] Shrink `SiriOrbView` size from 108 to 80 and the Studio frame height so the window does not grow.
- [x] Empty state is one muted line `No takes yet`. Do not draw five placeholder rows.
- [x] Do not add a second SwiftData model. Do not cache takes on `DictationSessionController`.
- [x] A sixth take appears at the top. The sixth oldest leaves the strip and remains in Settings, History.

**You see.**

- [x] After five successful dictations, Studio lists five rows and the orb still fits above the listen button.
- [x] Settings, History still lists all records.
- [x] Copy on a row puts `polishedText` on the pasteboard.
- [x] Log after insert still contains `Dictation complete`. Evidence `docs/media/PR-recent-dictation-complete.txt`. Live Listen then Stop, `Dictation complete via clipboard chars=39`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [x] A helper or view-model test that six records yield five ids, newest first. Run `xcodebuild test -project WisprFlowAlt.xcodeproj -scheme Cadence -destination "platform=macOS"`. `RecentTakesStripTests` passed.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.6-fast-xhigh` at the PR head, per the boot recipe.

- [x] Lane 1. Fresh store, open Studio. Save `studio-empty.png`. Pass when the strip shows `No takes yet` and the listen button is visible without scrolling. Evidence `docs/media/PR-recent-review-studio-empty.txt` (AX). Screen Recording TCC blocked PNG.
- [x] Lane 2. One injected take. Save `studio-one.png`. Pass when one row shows a clip of the polished text. Evidence `docs/media/PR-recent-review-studio-one.txt` (AX). Store restored to 32 takes after.
- [x] Lane 3. Five injected takes. Save `studio-five.png`. Pass when exactly five rows show. Evidence `docs/media/PR-recent-review-studio-five.txt` (AX).
- [x] Lane 4. A sixth injected take. Save `studio-sixth.png`. Pass when the newest row is first and the oldest of the six is gone from Studio. Evidence `docs/media/PR-recent-review-studio-sixth.txt` (AX). Store restored to 32 takes after.
- [x] Lane 5. Open Settings, History after lane 4. Save `settings-history-six.png`. Pass when all six records remain. Evidence `docs/media/PR-recent-review-settings-history-six.txt`.
- [x] Lane 6. Copy the second row. Save `studio-copy.png`. Pass when the pasteboard string equals that row's polished text. Pasteboard was `Are you aware of Gronkboard? Do what it does?`.
- [x] Lane 7. Hold Fn so state is recording. Save `studio-live.png`. Pass when a live partial or Listening line is visible and the strip does not jump the listen button off-screen. Evidence `docs/media/PR-recent-review-studio-live.txt` (Listen button, not Fn).
- [ ] Lane 8. Microphone denied. Save `studio-mic-denied.png`. Pass when Allow Microphone still fits and the strip remains. Cadence Local Dev already has Microphone. CadenceProbe now logs `mic=true`. Do not `tccutil reset`. Box stays open. Evidence `docs/media/PR-recent-mic-denied-probe.txt`.
- [x] Lane 9. VoiceOver rotor on the first row. Save `studio-vo.png`. Pass when the accessibility label is the full polished text, not the clipped line. AX name on the long row was the full `polishedText`.
- [x] Lane 10. Measure Studio window. Save `studio-frame.png`. Pass when window height is at most 560 points. AX size `360x552`.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. SwiftData fetch of `TranscriptRecord` count 5 versus loading the full History list.
- [ ] Probe. Instruments time profiler on Studio appear, or a DEBUG log of fetch duration, at trunk (full card, no strip) and at the head, interleaved.
- [ ] Baseline. Record trunk Studio appear to first paint in milliseconds first.
- [ ] Rule. Head Studio appear to first paint must be at most trunk plus 50 ms. Fail if the strip scans every record on the main thread.

**Review gate.** The operator reviews before merge.

- [ ] Copy lane 1, lane 3, lane 4, and lane 7 screenshots into `docs/media/PR-recent-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of the change on a lane VM. Save it as `docs/media/PR-recent-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] Root appends the PR to the Graphite stack. The operator lands it.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence

No throwaway SwiftUI window was built. Studio is already 360 by 560 with a 132-point orb and an 88-point last-dictation body. Those numbers are in `CadenceStudioView.swift`. A prototype would have been PR-recent itself.

Unproven until PR-recent live lanes. Whether five 22-point rows plus a live line still leave the listen button on screen at 560 height. If a lane fails, shrink the orb further. Do not grow the window.

## Appendix B. Alternatives rejected

**Disclosure chevron that expands History.** Hides five takes behind a click. The operator asked for them on the front page. Rejected per experience-first.

**Horizontal chips.** Five chips clip worse than one-line rows. Horizontal scroll fights a 360-point window. Rejected.

**New `RecentTake` SwiftData type.** Duplicates `TranscriptRecord`. Two writes on every inject. Rejected per laziness-protocol and model-the-domain. The domain object already exists.

**Session array of the last five strings.** Diverges from History after Clear History. Rejected. `@Query` is the single source of truth.

**Chosen shape.** `RecentTakesStrip` is a SwiftUI view over `@Query`. CadenceStudioView owns layout only. Public surface is the view plus `livePartial`. Complexity stays in SwiftData and one `prefix(5)`.

**Call sites.**

```swift
RecentTakesStrip(livePartial: appModel.speech.partialTranscript, isLive: isListening || isBusy)
```

Copy uses `polishedText`. Listening uses `livePartial` as the first row and still shows up to four saved takes under it.

## Appendix C. Risks

Native Cadence has no `control-ui` skill. Live lanes use `screencapture` and logs. Watch false passes from a stale `/Applications/Cadence.app`. Always launch the built copy under `/tmp/swarm-cadence/`.

PR-recent can overflow 560 height. Watch lane 10. The owner shrinks the orb before raising the frame.

Clear History in Settings empties the strip on the next query. That is correct. Do not special-case it.

Compare Lab stays in the repo. PR-docs only fences the README. A public GitHub push still ships Wispr upload code. Watch that if the operator later makes the repo public.

## Appendix D. Links and reading list

Read `docs/ARCHITECTURE.md`, `docs/LEARNINGS.md`, and `docs/DISTRIBUTION.md` before PR-clean.

PR-recent gets `pstack/skills/how/SKILL.md` on `CadenceStudioView` and `TranscriptRecord` if the owner did not write this plan.

Do not run `pstack/skills/interrogate/SKILL.md` unless the operator contests the five-row strip.

Trail per `pstack/skills/show-me-your-work/SKILL.md` stays local in each owner's `decisions.tsv`. Do not commit it.
