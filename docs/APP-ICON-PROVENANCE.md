# Cuelixa App Icon Provenance Record

The qualified macOS application preserves the approved `Assets.xcassets/AppIcon.appiconset` from the accepted native-port baseline byte-for-byte.

## Original vector master

The repository also retains the original first-party SVG master as:

`docs/assets/cuelixa-icon.svg`

Its SHA-256 is:

`cf456e5ee218e1db4b439b2110d992edec90546d1163e7c2f0a8de1a54d5539d`

That checksum matches the earlier Cuelixa artwork integrity manifest retained with the project history. The same SVG source is present in the accepted Cuelixa 0.6.57 final-icon installer history and contains the established timed-caption mark using the canonical Cuelixa coral `#FF645A`.

The SVG is retained as provenance/design-source material. The released macOS application continues to ship the already-qualified raster AppIcon set; publication work does not silently regenerate or substitute those shipping icon bytes.

## Established from the distributed assets

- The shipping set contains standard macOS raster sizes from 16 px through 1024 px.
- The qualified macOS application adds no Apple artwork and ships no extracted SF Symbol artwork.
- Pixel inspection of the approved 1024 px raster identifies its dominant exact coral payload as sRGB `#FF645A` (`255, 100, 90`).
- The qualified macOS application uses that value only as Cuelixa's restrained semantic identity accent.
- The qualified macOS application does not redraw, recolor, or otherwise mutate the frozen raster icon set during repository/publication preparation.

## Publication presentation

README/project presentation should reference the vector master so the project icon remains reliably visible on GitHub without depending on the binary AppIcon transfer path. The AppIcon asset catalog remains the authoritative shipping resource used by Xcode.

