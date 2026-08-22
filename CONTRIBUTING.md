# Contributing

Cuelixa favors small, evidence-driven changes over broad rewrites.

Before opening a pull request:

1. Keep the native macOS product contract intact unless the change explicitly proposes a product decision.
2. Do not add external runtimes or dependencies when Apple platform APIs already satisfy the requirement.
3. Preserve local user data and existing libraries non-destructively.
4. Keep Swift 6 strict concurrency enabled and treat Swift warnings as errors.
5. Run `./VALIDATE-MAC.sh` on the supported macOS/Xcode toolchain when the change touches shipping code.
6. Update documentation only when behavior, requirements, privacy, security, or release mechanics actually changed.

Pull requests should explain the problem, the smallest justified solution, validation performed, and any user-visible impact.

Security vulnerabilities should follow [SECURITY.md](SECURITY.md), not public issue discussion.
