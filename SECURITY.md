# Security Policy

## Supported version

Security fixes target Cuelixa `0.7` (build `53`) on supported macOS releases.

## Reporting a vulnerability

Do not publish exploitable security details in a public issue. Use GitHub's private vulnerability reporting feature when it is enabled for this repository. If private reporting is unavailable, contact the repository maintainer privately through the contact method listed on the maintainer's GitHub profile.

Include enough information to reproduce and assess the issue: affected version/commit, macOS version, impact, reproduction steps, and any proof-of-concept material needed to demonstrate the problem safely.

## Scope

Relevant reports include unsafe file handling, privilege or permission problems, unintended data disclosure, code-execution paths, integrity failures, dependency/supply-chain problems, and security-sensitive concurrency or persistence defects.

Cuelixa does not require users to disable Gatekeeper or System Integrity Protection. Documentation or packages that instruct users to do so are considered release defects.
