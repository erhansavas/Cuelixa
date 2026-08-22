# Build and development

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

## GitHub Actions

GitHub CI runs the same source-integrity and application checks on an Apple-silicon `macos-26` runner with Xcode 26.6 selected explicitly. Manual interface, accessibility, performance, and runtime testing remain separate from hosted CI.

## Source integrity

`SOURCE-SHA256SUMS.txt` covers every tracked file except the manifest itself. Verify both the tracked path set and file digests with:

```sh
./Scripts/verify-source-manifest.sh
```
