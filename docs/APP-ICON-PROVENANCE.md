# Cuelixa App Icon Provenance Record

The macOS application now uses the first-party `CuelixaMac/AppIcon.icon` Icon Composer document as its authoritative app-icon source. The prior raster `Assets.xcassets/AppIcon.appiconset` remains in the repository as historical/provenance material; Xcode selects the matching `AppIcon.icon` document for the macOS 27 application.

## Original vector master

The repository also retains the original first-party SVG master as:

`docs/assets/cuelixa-icon.svg`

Its SHA-256 is:

`cf456e5ee218e1db4b439b2110d992edec90546d1163e7c2f0a8de1a54d5539d`

That checksum matches the retained Cuelixa artwork integrity manifest. The SVG contains the established timed-caption mark using the canonical Cuelixa coral `#FF645A`.

The SVG is retained as provenance/design-source material. Its caption mark was separated into three foreground SVG layers for Icon Composer; the system supplies the macOS mask and appearance treatment instead of receiving a pre-masked transparent canvas.

## Icon Composer source

`CuelixaMac/AppIcon.icon/icon.json` defines an opaque full-bleed gradient background and three ordered caption layers. The layers use automatic Liquid Glass treatment so Xcode can render the Default, Dark, Clear Light, Clear Dark, Tinted Light, and Tinted Dark macOS appearances from one source document. The foreground geometry stays inside the documented 1024-point Mac canvas safe area; no canvas mask or transparent border is baked into the source layers.

The document is included in the application target's Resources phase and its basename matches `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Native Xcode compilation is the source of truth for the generated bundle resources. Runtime appearance/rendering qualification uses macOS 27. Earlier macOS 26 rendering checks are retained only as historical evidence in the audit report.

## Established from the distributed assets

- The shipping set contains standard macOS raster sizes from 16 px through 1024 px.
- The qualified macOS application adds no Apple artwork and ships no extracted SF Symbol artwork.
- Pixel inspection of the approved 1024 px raster identifies its dominant exact coral payload as sRGB `#FF645A` (`255, 100, 90`).
- The qualified macOS application uses that value only as Cuelixa's restrained semantic identity accent.
- The native control accent asset uses deeper coral `#BD332B` so white selection text has sufficient contrast. The icon artwork and explicit identity accent remain `#FF645A`.
- The qualified macOS application does not redraw, recolor, or otherwise mutate the frozen raster icon set during repository/publication preparation.

## Publication presentation

README presentation uses `docs/assets/cuelixa-icon.png` and `cuelixa-icon-dark.png`, exported directly from the authoritative Icon Composer document with Xcode 27's `ictool`. The 512×512 Default and Dark renditions use the macOS platform and design generation 27. GitHub selects the matching image through a `picture` element. The original vector master and raster set remain available as provenance; they are no longer presented as the current app icon.

README screenshots were captured from the current macOS 27 application using an isolated library of generated silent WAV files and first-party sample captions. They show light/dark library appearance, the native missing-subtitle sheet, and actual sidecar playback. A temporary black backdrop behind the floating overlay keeps unrelated desktop content out of the capture. No lesson recording or personal library data is included.
