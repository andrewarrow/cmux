# simple

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | 繁體中文 | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

一款簡潔的 macOS 終端機 App：一個視窗、一個本機 Shell，沒有設定或帳號。

App 使用 SwiftUI 編寫。[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 提供終端機模擬器與偽終端機，讓互動式程式正常運作。

## 建置與執行

需要 macOS 14 或更新版本，以及 Xcode 隨附的 Swift 工具鏈。

```sh
swift run
```

只建置、不啟動 App：

```sh
swift build -c release
```

Shell 路徑取自環境變數 `SHELL`；未設定時使用 `/bin/zsh`。

## 授權

此 fork 的程式碼仍採用 [GPL-3.0-or-later](LICENSE)。SwiftTerm 則以 MIT 授權獨立散布；請參閱 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
