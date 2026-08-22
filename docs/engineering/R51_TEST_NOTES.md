# Cuelixa 0.6.65-r51 exact-target test record

Environment: macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, Apple silicon arm64.

## Automated qualification

- Debug: PASS
- Release: PASS
- Analyze: PASS
- SDK/API smokes: PASS
- Deterministic subtitle/database/playback-policy smokes: PASS
- Generated local AVFoundation playback smoke: PASS
- Strict concurrency: complete
- Warnings as errors: enabled
- Hardened Runtime: enabled
- App Sandbox: intentionally disabled
- Final validator: `VALIDATION PASSED — EXACT TARGET XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES`

Allowed warning scope: only the exact `appintentsmetadataprocessor` message `Metadata extraction skipped. No AppIntents.framework dependency found.` after the AppIntents absence guard passes. All other warnings and errors remain fatal.

## Manual regression

- Prepare All Subtitles → Cancel → Dismiss: PASS; the popover closed immediately.
- Reopen/retry after dismissal: PASS.
- Playback/resume/seek/subtitle behavior: PASS and unchanged.
- VoiceOver/accessibility release pass: accepted.
- Time Profiler/thermal: no sustained Cuelixa runaway; Thermal State Nominal.
- Allocations/Leaks: no visible Cuelixa-owned leak in the captured run.

Signing and DMG packaging are separate release-workflow gates; ad-hoc signing is not Developer ID signing or notarization.
