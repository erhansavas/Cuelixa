# Repository settings after publication

Apply these settings only after the repository exists publicly:

- Protect the default branch with a ruleset.
- Require the `macos-arm64-release` status check before merge; it includes the fail-closed source-manifest gate.
- Require pull requests, but require zero approving reviews for this single-developer repository.
- Dismiss stale approvals only if approving reviews are required in a future multi-maintainer setup.
- Block force pushes and deletion of the protected default branch.
- Protect `v*` release tags from update or deletion after publication; release tags are immutable.
- Restrict GitHub Actions to required actions/workflows and require full-length SHA pinning when practical.
- Keep default workflow token permissions read-only; grant write scopes only to a workflow that demonstrably needs them.
- Enable Dependabot alerts and security updates as appropriate.
- Enable secret scanning and push protection when available for the repository/account tier.
- Enable Private Vulnerability Reporting.
- Enable code scanning only with a Swift/macOS configuration that actually builds and reports useful results; do not require a permanently broken ceremonial check.
