# simple

[English](README.md) | Deutsch | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

Eine kleine Terminal-App für macOS: ein Fenster, eine lokale Shell, keine Einstellungen und keine Konten.

Die App verwendet SwiftUI. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) stellt den Terminal-Emulator und das Pseudo-Terminal bereit, damit interaktive Programme wie erwartet funktionieren.

## Erstellen und starten

Erforderlich sind macOS 14 oder neuer und die mit Xcode gelieferte Swift-Toolchain.

```sh
swift run
```

Ohne die App zu starten erstellen:

```sh
swift build -c release
```

Die Shell wird aus der Umgebungsvariable `SHELL` gelesen. Standardmäßig wird `/bin/zsh` verwendet.

## Lizenz

Der Code dieses Forks bleibt unter [GPL-3.0-or-later](LICENSE). SwiftTerm steht separat unter MIT-Lizenz; siehe [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
