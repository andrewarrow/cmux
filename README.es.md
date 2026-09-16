# simple

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | Español | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

Una pequeña app de terminal para macOS: una ventana, un shell local y sin ajustes ni cuentas.

La app está escrita con SwiftUI. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) proporciona el emulador de terminal y la pseudoterminal para que los programas interactivos funcionen correctamente.

## Compilar y ejecutar

Se requiere macOS 14 o posterior y la cadena de herramientas Swift incluida con Xcode.

```sh
swift run
```

Compilar sin abrir la app:

```sh
swift build -c release
```

El shell se obtiene de la variable de entorno `SHELL`. Si no está definida, se usa `/bin/zsh`.

## Licencia

El código de este fork sigue bajo [GPL-3.0-or-later](LICENSE). SwiftTerm se distribuye por separado bajo la licencia MIT; consulta [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
