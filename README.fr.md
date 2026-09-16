# simple

[English](README.md) | [Deutsch](README.de.md) | Français | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

Une petite application de terminal pour macOS : une fenêtre, un shell local, sans réglages ni compte.

L’application utilise SwiftUI. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) fournit l’émulateur de terminal et le pseudo-terminal nécessaires au bon fonctionnement des programmes interactifs.

## Compiler et lancer

macOS 14 ou une version ultérieure et la chaîne d’outils Swift fournie avec Xcode sont nécessaires.

```sh
swift run
```

Compiler sans lancer l’application :

```sh
swift build -c release
```

Le shell est défini par la variable d’environnement `SHELL`. À défaut, `/bin/zsh` est utilisé.

## Licence

Le code de ce fork reste sous [GPL-3.0-or-later](LICENSE). SwiftTerm est distribué séparément sous licence MIT ; voir [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
