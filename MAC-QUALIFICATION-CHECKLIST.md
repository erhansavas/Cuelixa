# Cuelixa 0.6.65-r51 — Target-Mac qualification checklist

Target: Apple Silicon, macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3.

## Compiler / project

- [ ] Freshly extract the exact R51 candidate and verify its SHA-256.
- [ ] Product → Clean Build Folder.
- [ ] Debug build: 0 errors, 0 warnings.
- [ ] Release build: 0 errors, 0 warnings.
- [ ] Product → Analyze: no unresolved defect.
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` remains active.
- [ ] `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` remains active.
- [ ] The historical `AttributedString.Runs.Element` tuple-pattern regression is absent.
- [ ] No redundant `try`/`await` warning remains after the primary type error is fixed.
- [ ] `./VALIDATE-MAC.sh` ends with `VALIDATION PASSED — EXACT TARGET XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES`.

## SwiftUI/AppKit lifecycle

- [ ] No `NSHostingView is being laid out reentrantly` diagnostic.
- [ ] No `layoutSubtreeIfNeeded` recursion diagnostic.
- [ ] No `Publishing changes from within view updates is not allowed` diagnostic.
- [ ] Main window reopen/close does not duplicate windows, toolbar items or sheets.
- [ ] Library window titlebar/sidebar/toolbar remain system-owned and stable through resizing/fullscreen.

## Library / filesystem

- [ ] Existing `~/podcast` is preserved and used without migration when present.
- [ ] Clean profile resolves the Music directory through Foundation and creates `Cuelixa` only as needed.
- [ ] Recursive add/rename/move/delete updates through FSEvents.
- [ ] FSEvents idle path has no recurring scanner timer.
- [ ] RootChanged and dropped-event recovery reconcile correctly.
- [ ] mp3/m4a/aac/flac/wav/ogg/opus fixtures are discovered; actual AVFoundation decode support is verified per format.
- [ ] Search and section changes do not trigger full transcript SHA verification.
- [ ] Rename/move of unchanged audio preserves content-hash resume/completion identity.
- [ ] Imports never overwrite collisions and leave no `.cuelixa-import-*` staging file after success/error/cancel.

## Database / cache

- [ ] Database migration from earlier schema opens cleanly and preserves state.
- [ ] Continue / Up Next / Completed counts and ordering remain correct.
- [ ] Durable transcript and legacy transcript candidates are independently memoized/verified.
- [ ] Same-size rapid SRT/manifest replacement invalidates stale memo state via filesystem signature change.
- [ ] Invalid/corrupt manifest or SRT is rejected.
- [ ] Valid same-basename sidecar SRT plays without retranscription.

## Player / subtitles

- [ ] Plain audio starts/stops correctly.
- [ ] Durable generated SRT starts correctly.
- [ ] Legacy valid SRT starts correctly.
- [ ] Sidecar SRT starts correctly.
- [ ] Resume inside a cue displays the cue immediately.
- [ ] Cue start is inclusive; cue end is exclusive.
- [ ] Authored overlap selects the most recently started active cue.
- [ ] Seek into a gap clears the prior cue.
- [ ] Rapid backward/forward seeks never display stale previous-track text.
- [ ] Slider drag updates UI/subtitle smoothly and performs one exact decoder seek on release.
- [ ] Play/pause, ±10, ±30 and hardware media commands remain synchronized.
- [ ] Now Playing title/duration/position/state stay coherent.
- [ ] AVPlayer item failure is surfaced to the user; audio never silently runs behind an expected-but-unreadable subtitle overlay.
- [ ] Player open/play/seek/close ×50 shows no accumulated observers/panels/memory growth.

## Speech / Prepare All

- [ ] `SpeechTranscriber.isAvailable` failure is handled gracefully.
- [ ] Equivalent English locale failure is handled gracefully.
- [ ] Required speech assets install only when absent.
- [ ] No microphone prompt is required for file-only transcription.
- [ ] Timed result runs generate readable, synchronized cues.
- [ ] Immediate playback of newly generated SRT succeeds without relaunch.
- [ ] Duplicate requests for the same content hash share one transcription job.
- [ ] Prepare All remains single-worker.
- [ ] Cancel during preparation/analysis/finalization/queue leaves no false-valid transcript.
- [ ] Serious/critical thermal state paces queued jobs without parallel model churn.

## Quit / ownership

- [ ] Quit idle.
- [ ] Quit while playing.
- [ ] Quit while scanning.
- [ ] Quit during import.
- [ ] Quit during transcription, cancel quit, continue safely, then quit again.
- [ ] Scanner cancellation completes before termination reply.
- [ ] Speech analyzer cancellation completes before termination reply.
- [ ] Import tasks are cancelled/awaited before termination reply.
- [ ] Carbon hotkeys and MediaPlayer command targets are removed on shutdown.

## Energy / performance / memory

- [ ] 10-minute settled idle: no recurring recursive scan work, stable memory, no unexpected CPU/disk wakeups.
- [ ] 10-minute audio playback: stable memory and no hidden main-library invalidation from player clock.
- [ ] Rapid search/section changes remain responsive on constrained Apple Silicon.
- [ ] 50 player cycles plateau in Allocations/Leaks.
- [ ] 20 prepare/cancel cycles plateau in Allocations/Leaks.
- [ ] Prepare All uses one analyzer worker and returns to low activity after completion.
- [ ] Time Profiler, Allocations, Leaks and current Energy tooling show no Cuelixa-origin runaway work.

## Accessibility / visual platform behavior

- [ ] VoiceOver order/labels are usable.
- [ ] Full Keyboard Access reaches sidebar, search, list/actions, sheets and player controls.
- [ ] Reduce Motion is respected.
- [ ] Reduce Transparency produces readable player/dialog surfaces.
- [ ] Increase Contrast remains readable.
- [ ] Light/dark and several macOS Accent Colors render correctly.
- [ ] Active/inactive window states remain legible.
- [ ] Minimum/default/large window, fullscreen, Spaces and external-display moves do not clip or strand UI.

## Console triage

- [ ] No Cuelixa-origin crash/assertion/concurrency/database/FSEvents/AVPlayer/Speech error remains unexplained.
- [ ] `com.apple.linkd.autoShortcut` is not suppressed or “fixed” with fake intents; investigate only with behavior correlation.
- [ ] ViewBridge/DetachedSignatures/AudioComponent/Fig* messages are classified only after behavior/error correlation, not by console text alone.

## Release

- [ ] Apache-2.0/license/provenance files are complete for the exact distributed tree.
- [ ] Release archive contains no DerivedData, build products, user media, xcuserdata, `.DS_Store`, or accidental secrets.
- [ ] Developer ID signing/notarization is completed and inspected before a public binary release.
