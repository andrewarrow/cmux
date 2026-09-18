# simple

English | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

A small macOS terminal app: one window, one local shell, no settings or accounts.

The app is written in SwiftUI. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) provides the terminal emulator and pseudo-terminal so interactive programs work as expected.

## Build and run

Requires macOS 14 or later and the Swift toolchain included with Xcode.

The normal development build is an executable:

```sh
swift build
```

Build without launching the app:

```sh
swift build -c release
```

To build and install the signed app bundle used for normal launches, run:

```sh
./scripts/build-app.sh "$HOME/Desktop/SimpleCmux.app"
```

The script keeps the app's bundle identifier and signs the bundle with the
first valid Apple Development or Developer ID identity in the local keychain.
You can select one explicitly with `SIMPLECMUX_SIGNING_IDENTITY`. macOS uses
the signed app's designated requirement to remember privacy approvals, so use
this script for updates instead of copying an unsigned executable into the
app bundle. Privacy approvals still have to be granted once in System
Settings; a build cannot grant or export them.

The shell comes from the `SHELL` environment variable, falling back to `/bin/zsh`.

## License

This fork's code remains under [GPL-3.0-or-later](LICENSE). SwiftTerm is separately licensed under MIT; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
