# simple

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | 한국어

macOS용 작은 터미널 앱입니다. 창 하나와 로컬 셸 하나만 있으며 설정이나 계정은 없습니다.

앱은 SwiftUI로 작성되었습니다. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)이 터미널 에뮬레이터와 의사 터미널을 제공해 대화형 프로그램도 정상적으로 실행됩니다.

## 빌드 및 실행

macOS 14 이상과 Xcode에 포함된 Swift 툴체인이 필요합니다.

```sh
swift run
```

앱을 실행하지 않고 빌드하려면 다음 명령을 사용하세요.

```sh
swift build -c release
```

셸은 환경 변수 `SHELL`에서 가져옵니다. 값이 없으면 `/bin/zsh`를 사용합니다.

## 라이선스

이 fork의 코드는 계속 [GPL-3.0-or-later](LICENSE)를 따릅니다. SwiftTerm은 MIT 라이선스로 별도 배포됩니다. 자세한 내용은 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.
