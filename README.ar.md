# simple

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | العربية | [Español](README.es.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

تطبيق طرفية صغير لنظام macOS: نافذة واحدة، وصدفة محلية واحدة، بلا إعدادات أو حسابات.

كُتب التطبيق باستخدام SwiftUI. توفّر [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) محاكي الطرفية والطرفية الوهمية اللازمة لتشغيل البرامج التفاعلية كما هو متوقع.

## البناء والتشغيل

يتطلب macOS 14 أو أحدث، وأدوات Swift المضمّنة مع Xcode.

```sh
swift run
```

للبناء من دون تشغيل التطبيق:

```sh
swift build -c release
```

يُحدَّد مسار الصدفة من متغير البيئة `SHELL`، ويُستخدم `/bin/zsh` عند غيابه.

## الترخيص

يبقى كود هذا الفرع خاضعًا لترخيص [GPL-3.0-or-later](LICENSE). أما SwiftTerm فتُوزّع بترخيص MIT منفصل؛ راجع [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
