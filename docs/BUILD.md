# Build and validation

These instructions apply to Cuelixa 0.7 (build 53).

## Requirements

- Apple silicon Mac
- macOS 27 or later
- Full Xcode; the current macOS 27 audit uses Xcode 27 beta 6 (`27A5252f`) and Swift 6.4

The deployment target is macOS 27.0 and the shipping architecture is `arm64`.

## Xcode

Open `CuelixaMac.xcodeproj`, select **Cuelixa → My Mac**, then build the Debug or Release configuration. Swift complete strict-concurrency checking and warnings-as-errors are enabled for the application target.

## Local checks

For the current macOS 27 validation with Xcode 27 beta 6 installed in Applications, select that toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./VALIDATE-MAC.sh
```

The script uses fresh DerivedData, checks the selected toolchain and project settings, builds Debug and Release, runs Analyze and deterministic smoke tests, and inspects the resulting `arm64` application binary. The default qualification environment is macOS 27.0, Xcode 27.0 (`27A5252f`), and Swift 6.4. Version overrides remain available for deliberate qualification of a newer toolchain.

The validation builds set `CODE_SIGNING_ALLOWED=NO`; native UI tests use ad-hoc signing. Validation does not change project signing settings or produce the downloadable release package.

The native UI tests use temporary libraries and assert that their database is created there. The `DEBUG` compilation condition enables this isolation only in Debug builds. UI checks exercise keyboard navigation, search, completion persistence, sidecar playback, accessibility, and window resizing. The appearance test briefly switches the test Mac between light and dark mode and restores its original setting during teardown.

## GitHub Actions

GitHub CI uses the Apple silicon `xcode-27` image with Xcode 27 beta 6 selected explicitly. [GitHub currently hosts this image on macOS 26](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), so workflows set `CUELIXA_BUILD_ONLY=1`: they compile all test targets and smoke executables for macOS 27, build Debug and Release, run Analyze, and verify the release bundle. They do not launch the macOS 27 app on an unsupported host.

The full default validator, including all runtime and UI tests, must pass on macOS 27 before a release. Build-only CI is not runtime qualification.

## Source integrity

`SOURCE-SHA256SUMS.txt` covers every tracked file except itself and detects accidental tree drift. It is stored with the source, so it is not an independent trust root. Verify both the path set and file digests with:

```sh
./Scripts/verify-source-manifest.sh
```
