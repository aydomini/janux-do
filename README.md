# JANUX DO

A desktop forum browser built with Flutter.

No Electron. No webview wrappers. Native rendering. Runs on macOS, Windows, and Linux.

## Features

- Browse and read forum threads
- Material Design 3 with dark mode and dynamic color
- Image lazy loading and caching
- Multi-language support (Simplified Chinese, Traditional Chinese, English)
- Keyboard shortcuts on desktop
- Native window effects (macOS sidebar, Windows Mica)

## Quick Start

```bash
melos bootstrap && just sync && just run -- -d macos
```

Other platforms:

```bash
just run -- -d windows
just run -- -d linux
```

## Development

```bash
just test                          # run all tests
just test -- test/forum_adapter/   # parser tests only
just analyze                       # static analysis
just l10n                          # regenerate i18n code
```

## Build

```bash
just build -- macos --release
```

GitHub Actions provides manual macOS DMG builds.

## Tech Stack

Flutter / Riverpod / Dio / slang / re_highlight

## Disclaimer

This is an experimental third-party client built for educational purposes. Use at your own risk. Not affiliated with any forum operator.

## License

[GPL-3.0](LICENSE)
