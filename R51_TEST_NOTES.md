# Cuelixa 0.6.65-r51 exact-target final test notes

1. Fresh-extract the exact R51 candidate and verify its published SHA-256.
2. Run `./VALIDATE-MAC.sh` from Terminal.
3. Required validator result: `VALIDATION PASSED — EXACT TARGET XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES`.
4. The validator may allow only the already-scoped benign `appintentsmetadataprocessor` metadata-extraction warning; any other warning/error remains fatal.
5. Confirm the R51 regression directly: Prepare All Subtitles -> Cancel -> wait for cancelled summary -> Dismiss. The popover must close immediately without requiring an outside click and without leaving an empty `Preparing subtitles` surface.
6. Repeat the same flow once more to ensure Prepare All can reopen cleanly.
7. Existing playback/resume/seek/subtitle behavior should remain unchanged.
8. R50 Time Profiler predecessor evidence was nominal; no new performance architecture was introduced in R51. If the exact R51 validator and popover regression pass, no additional profiling is required solely for this presentation-state fix unless runtime behavior changes.
9. Signing/notarization/publication remain separate release actions.
