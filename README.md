# ОмАВИАТ Расписание

Нативное приложение SwiftUI для расписания групп Омского авиационного колледжа. Минимальная версия iOS — 17. Приложение загружает актуальные корпуса и группы с `oat.ru`, показывает недельную сетку занятий, кэширует расписание и изменения в SwiftData, сравнивает нормализованные снимки и создаёт локальные уведомления.

## Структура

- `Sources/OATSchedule/Models` — доменные типы и календарь `Asia/Omsk`.
- `Sources/OATSchedule/Core` — URLSession клиент, SwiftSoup parser, сервисы, SwiftData, diff, уведомления и фоновые задачи.
- `Sources/OATSchedule/Features` — onboarding, расписание, изменения, настройки.
- `Tests/OATScheduleTests/Fixtures` — компактные структурные HTML примеры для regression tests.
- `docs/OAT_RESEARCH.md` — фактическая структура источника и ограничения исследования.

## Открыть и запустить на Mac

Требуются Xcode 15+ и XcodeGen 2.39+.

```sh
brew install xcodegen
xcodegen generate
open OATSchedule.xcodeproj
```

Windows не содержит Apple SDK, Xcode, `xcodebuild` или Swift в PATH проекта. Поэтому генерацию Xcode-проекта, сборку и tests в этой среде выполнить нельзя.

## GitHub Actions: IPA

Workflow `.github/workflows/ios-ipa.yml` собирает IPA на macOS runner. Для подписи задайте секреты в **Settings → Secrets and variables → Actions**: `IOS_CERTIFICATE_BASE64` (экспортированный Apple Distribution `.p12` в Base64), `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` и `IOS_TEAM_ID`. Сертификат, профиль и пароль не добавляйте в Git. Workflow экспортирует IPA как Actions artifact, не загружая её в App Store Connect.

Для Base64 на Mac:

```sh
base64 -i Distribution.p12 | pbcopy
base64 -i App.mobileprovision | pbcopy
```

После push откройте Actions → iOS build and IPA и скачайте IPA из Artifacts.
