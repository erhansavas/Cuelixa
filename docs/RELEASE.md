# macOS release procedure

Cuelixa's public GitHub build is intentionally distributed without a paid Apple Developer ID certificate. The release therefore uses an ad-hoc-signed application inside a read-only DMG and does **not** claim Apple notarization or verified developer identity.

## Public identity

- Release title: `Cuelixa 0.6.65`
- Git tag: `v0.6.65`
- macOS package: `Cuelixa-0.6.65-macOS-arm64.dmg`
- Checksum: `Cuelixa-0.6.65-macOS-arm64.dmg.sha256`
- Internal engineering build: `51`
- Qualified engineering identifier: `0.6.65-r51`

Engineering labels such as `r51`, `native`, and `candidate` do not belong in public artifact names.

## Release gate

1. Freeze the exact source revision.
2. Verify `MARKETING_VERSION = 0.6.65`, `CURRENT_PROJECT_VERSION = 51`, deployment target `26.0`, and `arm64` architecture.
3. Run `./VALIDATE-MAC.sh` on the exact target Mac for authoritative qualification. CI is an additional regression gate, not a replacement for that evidence.
4. Require clean Debug, Release, Analyze, smoke tests, Swift strict-concurrency checks, and warnings-as-errors.
5. Reconfirm the manual runtime, accessibility, performance/thermal, and memory/leak evidence recorded in `docs/QUALIFICATION.md` and `docs/engineering/R51_TEST_NOTES.md`.
6. Build Release for Apple silicon with Hardened Runtime enabled.
7. Apply an ad-hoc code signature and verify it with `codesign --verify --deep --strict`.
8. Create a read-only UDZO DMG containing `Cuelixa.app` and an `Applications` symlink.
9. Verify the DMG with `hdiutil verify`, mount it read-only, and re-check the embedded app's architecture and code signature.
10. Generate SHA-256 only after the DMG is frozen; immediately verify the checksum.
11. Publish the DMG and its `.sha256` file together under the matching Git tag/release.

## First launch

Because a free ad-hoc-signed build has no Apple Developer ID/notarization ticket, macOS can block the first launch of a downloaded copy. The supported user path is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**. This is preferable to disabling Gatekeeper or asking users to run `xattr`, disable SIP, or weaken system security.

A warning-free first launch for software downloaded outside the Mac App Store requires Apple Developer ID signing/notarization and is outside this project's no-paid-account distribution model.

## Release immutability

Do not move or rewrite an already-published release tag to correct a defect. Publish a new corrective version and new checksums instead.
