# OATSchedule Android

Нативная Android-версия «ОмАВИАТ Расписание» на Kotlin + Jetpack Compose.

Поддерживает выбор корпуса и группы, расписание с двухнедельным циклом, прямую загрузку изменений с `/timetable/Changes/bN/<date>`, локальный кеш, светлую/тёмную тему, анимации и уведомления об изменениях через WorkManager.

## Сборка

Требования: JDK 17 и Android SDK 35.

### macOS / Linux

```bash
cd android
chmod +x gradlew
./gradlew assembleDebug
```

### Windows

```bat
cd android
gradlew.bat assembleDebug
```

Скрипты `gradlew`/ `gradlew.bat` сами скачивают Gradle 8.9, поэтому бинарный wrapper jar в репозитории не нужен.

Готовый APK:

```
android/app/build/outputs/apk/debug/app-debug.apk
```

GitHub Actions также публикует debug APK как artifact **OATSchedule-Android-debug**.
