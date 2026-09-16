# simple

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | 日本語 | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

macOS 向けの小さなターミナルアプリです。ウィンドウとローカルシェルはそれぞれ 1 つで、設定やアカウントはありません。

アプリは SwiftUI で作られています。[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) がターミナルエミュレーターと擬似端末を提供するため、対話型プログラムも動作します。

## ビルドと起動

macOS 14 以降と、Xcode に含まれる Swift ツールチェーンが必要です。

```sh
swift run
```

アプリを起動せずにビルドする場合：

```sh
swift build -c release
```

シェルは環境変数 `SHELL` から取得します。設定されていない場合は `/bin/zsh` を使います。

## ライセンス

このフォークのコードは [GPL-3.0-or-later](LICENSE) の対象です。SwiftTerm は MIT ライセンスで個別に配布されています。[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。
