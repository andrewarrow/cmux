# simple

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | 简体中文 | [한국어](README.ko.md)

一个简洁的 macOS 终端应用：一个窗口、一个本地 Shell，没有设置或账户。

应用使用 SwiftUI 编写。[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 提供终端模拟器和伪终端，让交互式程序正常运行。

## 构建和运行

需要 macOS 14 或更高版本，以及 Xcode 附带的 Swift 工具链。

```sh
swift run
```

仅构建、不启动应用：

```sh
swift build -c release
```

Shell 路径取自环境变量 `SHELL`；未设置时使用 `/bin/zsh`。

## 许可证

此 fork 的代码继续采用 [GPL-3.0-or-later](LICENSE)。SwiftTerm 单独采用 MIT 许可证；请参阅 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
