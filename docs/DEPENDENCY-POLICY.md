# Dependency policy

Cuelixa prefers platform frameworks already shipped with supported macOS versions.

Any proposed third-party runtime dependency must document:

- why a system framework cannot satisfy the requirement;
- exact upstream/version and update strategy;
- architecture/minimum-macOS support;
- runtime memory/energy impact;
- signing/notarization implications;
- source and binary license obligations;
- whether the dependency introduces GPL/copyleft or other Apache-2.0 compatibility constraints.

Shipping code must not assume Homebrew, Python, ffmpeg, Whisper, Rosetta, `/opt/homebrew`, or a developer-machine path. CI-only actions must be pinned to immutable full commit SHAs and reviewed before updates.
