# Build and development

The qualification toolchain for 0.6.65-r51 is Xcode 26.6 (17F113), which includes Swift 6.3.3. The deployment target is macOS 26.0 and the shipping architecture is generic `arm64`.

## Xcode

Open `CuelixaMac.xcodeproj`, select `Cuelixa` → `My Mac`, use **Product → Clean Build Folder**, and build Debug and Release with the Xcode 26.6 toolchain.

## Exact target qualification

On the required target Mac — macOS 26.6.2, Apple Silicon, Xcode 26.6 (17F113) — run:

```sh
./VALIDATE-MAC.sh
```

The validator rejects the wrong macOS patch version, Xcode build, Swift version, CPU architecture, warning, build setting, or native-binary architecture before a candidate can be treated as compiler-qualified. It uses fresh DerivedData and performs clean Debug, clean Release, Release Analyze, SDK smokes, deterministic project smokes, and release-binary inspection.

The validation build deliberately sets `CODE_SIGNING_ALLOWED=NO`; it does not alter project signing settings and is not a distributable signed artifact.

## GitHub Actions

GitHub CI runs on the `macos-26` arm64 image and pins `DEVELOPER_DIR` to `/Applications/Xcode_26.6.app/Contents/Developer`. Because GitHub controls the runner OS patch level, CI uses `CUELIXA_CI_MODE=1`. That mode is deliberately incapable of claiming exact macOS 26.6.2 target qualification.

## Runtime qualification

Use `MAC-QUALIFICATION-CHECKLIST.md` and `R51_TEST_NOTES.md` on the exact packaged bytes. Performance, energy, memory, accessibility, and visual claims must come from the target candidate, not from CI or Linux host checks.
