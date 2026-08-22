# Repository settings after publication

Apply these settings only after the repository exists publicly:

- Protect the default branch with a ruleset.
- Require the `macos-arm64-release` status check before merge.
- Require pull requests and dismiss stale approvals when high-risk code changes warrant review.
- Block force pushes and deletion of the protected default branch.
- Restrict GitHub Actions to required actions/workflows and require full-length SHA pinning when practical.
- Keep default workflow token permissions read-only; grant write scopes only to a workflow that demonstrably needs them.
- Enable Dependabot alerts and security updates as appropriate.
- Enable secret scanning and push protection when available for the repository/account tier.
- Enable Private Vulnerability Reporting.
- Enable code scanning only with a Swift/macOS configuration that actually builds and reports useful results; do not require a permanently broken ceremonial check.
