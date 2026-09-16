# simple

English | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

A small macOS terminal app: one window, one local shell, no settings or accounts.

The app is written in SwiftUI. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) provides the terminal emulator and pseudo-terminal so interactive programs work as expected.

## Build and run

Requires macOS 14 or later and the Swift toolchain included with Xcode.

```sh
swift run
```

Build without launching the app:

```sh
swift build -c release
```

The shell comes from the `SHELL` environment variable, falling back to `/bin/zsh`.

## License

This fork's code remains under [GPL-3.0-or-later](LICENSE). SwiftTerm is separately licensed under MIT; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
