# GitHub repository controls

This document records the repository controls that protect `main` and the release workflow. Source-controlled workflows define CI behavior; settings configured in GitHub itself should be checked in GitHub Settings before a release.

## `main` protection

The active `Protect main` ruleset applies to the default branch and has no bypass actors. It:

- blocks branch deletion;
- blocks non-fast-forward updates;
- requires linear history;
- requires pull requests before merge;
- requires review-thread resolution;
- requires the `macos-arm64-release` status check with strict required-status behavior.

The ruleset allows squash and rebase merges. Release work must not weaken or bypass these protections.

## Workflow policy

Permanent workflows need a clear repository purpose, least-privilege `permissions`, and third-party actions pinned to immutable full commit SHAs. Release-only write scopes belong on the release job that needs them; ordinary CI stays read-only.

Temporary audit or remediation workflows are development infrastructure and must not remain in a release tree.

Code scanning is included only when the Swift/macOS CodeQL workflow builds and reports reliably. A permanently failing workflow would create noise rather than useful coverage.

### CodeQL status

Swift CodeQL was evaluated on the 0.7.1 release candidate using GitHub's supported manual-build model and documented Xcode compatibility settings: signing disabled, compilation caching disabled, the Swift integrated driver disabled, and one `arm64` architecture. CodeQL initialization and Swift extractor setup succeeded, but the traced Xcode build still failed without an actionable compiler diagnostic that justified another narrow correction.

Because CodeQL is optional for this project and the native validator is an independent release gate, the workflow was removed instead of leaving a known-red or speculative check. This is a deliberate coverage trade-off; Xcode Analyze, tests, and review are not claimed to provide equivalent CodeQL coverage. Reintroduce CodeQL only when a future toolchain/workflow combination demonstrates reliable Swift analysis.

## GitHub-hosted security settings

The following controls live outside the repository tree and should be checked in GitHub Settings before a public release:

- Dependabot alerts and security updates;
- secret scanning and push protection;
- Private Vulnerability Reporting;
- default workflow-token permissions remain read-only unless a workflow explicitly overrides them;
- immutable protection for published `v*` tags when configured separately from the `main` ruleset.

Do not treat this file alone as proof that a GitHub-hosted setting is enabled.
