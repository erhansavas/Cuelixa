# Cuelixa 0.6.65-r51 engineering report

## Verified predecessor evidence

The exact R50 candidate was run on macOS 26.6.2 / Xcode 26.6 (17F113) / Apple Swift 6.3.3 / arm64 and passed the full validator, including clean Debug, clean Release, Analyze, SDK smokes, deterministic subtitle/database tests, and generated local AVPlayer playback. Product > Analyze was also reported successful independently.

A roughly three-minute Time Profiler capture on the target Mac showed Thermal State `Nominal`, bursty rather than sustained CPU activity, and no visible runaway CPU loop. This is predecessor runtime evidence only; R51 changes one shipping Swift presentation file and therefore requires a fresh exact-byte validator/UI confirmation.

## R51 defect

Exact-target UI testing exposed a real presentation lifecycle defect in Prepare All Subtitles:

1. Start Prepare All.
2. Cancel it.
3. Press Dismiss on the final/cancelled batch summary.
4. The model summary was cleared, but the SwiftUI popover presentation binding remained true.
5. A visually empty/stale `Preparing subtitles` popover could remain until an outside click or framework-driven dismissal.

## Root cause

`BatchStatusPopover` owned no reference to the parent's `showingBatchStatus` state. Its `Dismiss` action called only `model.hideBatch()`. Clearing `BatchPresentation` did not guarantee that SwiftUI would dismiss the already-presented popover.

## R51 correction

`BatchStatusPopover` now receives `@Binding var isPresented: Bool` from `MainView`. Its inactive-summary `Dismiss` action performs both operations:

- clear the inactive batch presentation via `model.hideBatch()`;
- set the popover presentation binding to `false` immediately.

No transcription, cancellation, Speech, cache, AVFoundation, database, scanner, subtitle timing, or playback logic was changed.

`VALIDATE-MAC.sh` now contains `BATCH_POPOVER_DISMISS_GUARD` so this exact lifecycle contract cannot silently regress.

## Qualification status

Host/static packaging checks can establish source/package integrity and the presence of the regression guard. Exact Xcode 26.6 qualification for R51 remains required because `MainView.swift` changed. The required first target check is the normal `./VALIDATE-MAC.sh`, followed by a short Prepare All -> Cancel -> Dismiss UI confirmation.
