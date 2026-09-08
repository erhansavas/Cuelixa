# Build and validation

These instructions apply to Cuelixa 0.6.66 (build 52).

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Xcode 26.6 (`17F113`)
- Swift 6.3.3

The deployment target is macOS 26.0 and the shipping architecture is `arm64`.

## Xcode

Open `CuelixaMac.xcodeproj`, select **Cuelixa → My Mac**, then build the Debug or Release configuration. Swift complete strict-concurrency checking and warnings-as-errors are enabled for the application target.

## Local checks

Run the full build and test sequence on a supported Mac with:

```sh
./VALIDATE-MAC.sh
```

The script uses fresh DerivedData, checks the selected toolchain and project settings, builds Debug and Release, runs Analyze and deterministic smoke tests, and inspects the resulting `arm64` application binary.

The validation build sets `CODE_SIGNING_ALLOWED=NO`; it does not change project signing settings or produce the downloadable release package.

For the macOS 27 compatibility check with Xcode 27 beta 6 installed in Applications, select that toolchain for the command and declare the exact versions being tested:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CUELIXA_MACOS_VERSION=27.0 \
CUELIXA_XCODE_VERSION=27.0 \
CUELIXA_XCODE_BUILD=27A5252f \
CUELIXA_SWIFT_VERSION=6.4 \
./VALIDATE-MAC.sh
```

The native UI tests use temporary libraries and assert that their database is created there. The `DEBUG` compilation condition enables this isolation only in Debug builds. UI checks exercise keyboard navigation, search, completion persistence, sidecar playback, accessibility, and window resizing. The appearance test briefly switches the test Mac between light and dark mode and restores its original setting during teardown.

## GitHub Actions

GitHub CI runs the same source-integrity and application checks on an Apple-silicon `macos-26` runner with Xcode 26.6 selected explicitly. Manual interface, accessibility, performance, and runtime testing remain separate from hosted CI.

## Source integrity

`SOURCE-SHA256SUMS.txt` covers every tracked file except itself and detects accidental tree drift. It is stored with the source, so it is not an independent trust root. Verify both the path set and file digests with:

```sh
./Scripts/verify-source-manifest.sh
```
