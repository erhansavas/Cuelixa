# GitHub repository controls

This document separates repository controls verified through the GitHub API from settings that still require a manual GitHub UI check. It must not be read as proof of controls that were not observable during the audit.

## Verified for `main`

The active `Protect main` ruleset currently applies to the default branch and has no bypass actors. It:

- blocks branch deletion;
- blocks non-fast-forward updates;
- requires linear history;
- requires pull requests before merge;
- requires review-thread resolution;
- requires the `macos-arm64-release` status check with strict required-status behavior.

The ruleset allows squash and rebase merge methods. The 0.7.1 release process does not weaken or bypass these protections.

## Workflow policy

Permanent workflows should have a clear repository purpose, use least-privilege `permissions`, and pin third-party actions to immutable full commit SHAs. Release-only write scopes belong on the release job that needs them; ordinary CI stays read-only.

Temporary audit/remediation workflows are development infrastructure and must not survive in a release tree.

Code scanning is included only when the Swift/macOS CodeQL workflow actually builds and reports successfully. A permanently failing ceremonial security workflow is worse than an explicitly documented omission.

## Manual settings to verify in GitHub

The connector used for the 0.7.1 audit cannot verify or change every account/repository security setting. Before public release, confirm in GitHub Settings as applicable:

- Dependabot alerts/security updates;
- secret scanning and push protection;
- Private Vulnerability Reporting;
- default workflow-token permissions remain read-only unless a workflow explicitly overrides them;
- immutable protection for published `v*` tags if configured separately from the `main` ruleset.

Do not document any of these as active solely because this file recommends them.
