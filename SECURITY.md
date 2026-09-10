# Security Policy

## Supported version

Security and integrity fixes target Cuelixa `0.7.2` (build `55`) on its supported macOS release line.

## Reporting a vulnerability

Do not publish exploitable security details in a public issue. Use GitHub's private vulnerability reporting feature when it is enabled for this repository. If private reporting is unavailable, contact the repository maintainer privately through the contact method listed on the maintainer's GitHub profile.

Include enough information to reproduce and assess the issue: affected version/commit, macOS version, impact, reproduction steps, and any proof-of-concept material needed to demonstrate the problem safely.

## Scope

Relevant reports include unsafe local-file handling, unintended data disclosure, code-execution paths, integrity failures, dependency/supply-chain problems, and security-sensitive concurrency or persistence defects.

Cuelixa is an **unsandboxed local application**. It does not claim isolation from a malicious process already executing as the same macOS user. Its symlink, regular-file, bounded-read, copy-verification, content-identity, SQLite, and atomic-publication checks are defensive software-engineering boundaries around app-owned/local data; they are not a claim that Cuelixa is a security product.

See [Architecture](docs/ARCHITECTURE.md) for the precise filesystem and concurrency invariants.

Cuelixa does not require users to disable Gatekeeper or System Integrity Protection, change Secure Boot, use Recovery mode, or clear quarantine globally. Documentation or packages that require those workarounds are considered release defects.
