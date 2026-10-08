# Levels

A per-app volume mixer for macOS. Choose a menu bar popover or Dynamic Island.

**macOS 14.2+ · Universal Apple Silicon + Intel build · No audio driver**

## Screenshots

| Menu Bar Popover | Dynamic Island |
| --- | --- |
| <img src="docs/screenshots/levels-popover.jpg" alt="Levels menu bar popover with per-app volume controls" width="400"> | <img src="docs/screenshots/levels-dynamic-island.jpg" alt="Levels expanded Dynamic Island with per-app volume controls" width="400"> |

## Install

1. [Download the test DMG](https://github.com/LeeSinLiang/Levels/releases/download/v0.1.0-test/Levels-0.1.0-universal-test.dmg).
2. Drag **Levels.app → Applications**, eject the DMG, and open Levels.
3. Click **Enable App Volume**, allow **System Audio Recording**, then **Check Again** if needed.

The test build is **not notarized**. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** for a copy you trust. [Apple's instructions](https://support.apple.com/102445).

For setup help, open **••• → Levels Setup Guide**.

## Features

- Per-app volume and mute, with saved settings.
- Active apps first, plus search and output controls.
- Switch interfaces in **••• → Display Mode**.

Audio stays in memory; it is never saved or uploaded. Mono/stereo output only; volume is per app, not per browser tab. [Tested compatibility](docs/VERIFICATION.md).

## Build

Requires Swift 6 and Apple's Command Line Tools.

```sh
zsh scripts/build-app.sh
open "build/Levels.app"
zsh scripts/test.sh
```

[Packaging and release instructions](docs/RELEASING.md).
