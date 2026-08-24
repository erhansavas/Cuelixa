# Changelog

## Cuelixa 0.6.66 (build 52)

- Validate the legacy library root before selecting it and isolate filesystem paths per process.
- Serialize imports, verify copied bytes, prevent destination races, and surface per-file failures.
- Reconcile scanner results with one prepared-statement SQLite transaction and skip hashing unchanged files.
- Add Swift Testing integration, isolated UI launch coverage, database/import/path tests, and performance metrics.
- Avoid redundant AppKit overlay assignments while preserving 10 Hz playback timing.
- Derive release identity from Xcode metadata and attest release artifacts through GitHub Actions.

Distribution is free and ad-hoc signed. The release is not Apple Developer ID signed or notarized.
