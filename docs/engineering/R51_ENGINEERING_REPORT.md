# Cuelixa 0.6.65-r51 engineering report

## Scope

R51 is the qualified native macOS application baseline for marketing version `0.6.65` / build `51`. The application targets Apple silicon, macOS 26.0 or later, Xcode 26.6 (17F113), Swift 6.3.3, complete strict-concurrency checking, warnings-as-errors, and Hardened Runtime.

## R51 defect and correction

Exact-target UI testing exposed a presentation lifecycle defect in Prepare All Subtitles: after cancellation, pressing `Dismiss` cleared the model summary but could leave an empty stale popover presented.

`BatchStatusPopover` now receives the parent's presentation binding. Its inactive-summary action clears the batch presentation and sets that binding to `false` immediately. `BATCH_POPOVER_DISMISS_GUARD` protects the source contract.

No transcription, cancellation, Speech, cache, AVFoundation, database, scanner, subtitle timing, or playback logic changed for this correction.

## Exact-target qualification

The exact R51 candidate passed on macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, and arm64:

- clean Debug build;
- clean Release build;
- Release Analyze;
- SDK/API and deterministic project smokes;
- generated local AVFoundation playback smoke;
- strict warning/error filtering;
- release-setting and arm64 Mach-O inspection.

Final validator result:

`VALIDATION PASSED — EXACT TARGET XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES`

The only accepted Xcode tool warning was the exact `appintentsmetadataprocessor` metadata-extraction warning documented in [Qualification](../QUALIFICATION.md). No AppIntents dependency or entitlement was added.

## Runtime and UI evidence

- local MP3 playback, duration, resume, readiness, confirmed time advance, seeks, pause/resume, and end-state behavior passed;
- Prepare All → Cancel → Dismiss closed immediately and the flow reopened cleanly;
- accessibility testing exposed no blocking release defect;
- Time Profiler showed no sustained Cuelixa CPU runaway and Thermal State remained Nominal;
- Allocations/Leaks showed no visible Cuelixa-owned leak in the captured run.

Power Profiler was unsupported for macOS in the tested Instruments version; no unsupported power-profile claim is made.

## Publication preservation rule

Repository/documentation/release automation may be reorganized without rewriting the qualified shipping application. Every file under `CuelixaMac/` and the Xcode project must remain byte-identical to the authoritative R51 source unless a concrete compiler or runtime defect proves a new engineering revision is required.
