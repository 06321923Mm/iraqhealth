# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Iraq Health (المدار الطبي) is a Flutter web/mobile app for browsing Iraqi healthcare providers. It uses a hosted Supabase backend (PostgreSQL) and Firebase (Android-only). The primary development target is **Flutter Web** (Chrome).

### Environment

- **Flutter SDK 3.41.6** is installed at `/opt/flutter`. Ensure `PATH` includes `/opt/flutter/bin`.
- Dart SDK 3.11.4 is bundled with the Flutter SDK.
- Chrome is pre-installed and available as a Flutter device.

### Key commands

| Task | Command |
|---|---|
| Install deps | `flutter pub get` |
| Lint | `flutter analyze` |
| Test | `flutter test` |
| Build web | `flutter build web --release` |
| Dev server | `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0` |

### Known gotchas

- **Missing source files**: The `main.dart` imports `analytics_service.dart`, `doctor_model.dart`, `doctor_location_repository.dart`, and `location_picker_screen.dart` which were not committed in the original repo. Stub implementations have been added in this setup PR.
- **Supabase column aliasing**: The `doctors` table uses `latitude`/`longitude` column names, but the Flutter code maps them to `lat`/`lng` via Supabase select aliasing (`lat:latitude, lng:longitude`).
- **pub.dev advisory warnings**: `flutter pub get` emits `FormatException: advisoriesUpdated must be a String` warnings. These are harmless and caused by a pub.dev API format change; dependencies still resolve correctly.
- **Firebase**: Only used on Android (Crashlytics, FCM, Analytics). Web builds skip Firebase initialization (`if (!kIsWeb)`).
- **Admin panel**: Requires `ADMIN_PASSWORD` via `--dart-define=ADMIN_PASSWORD=...` at build time. Without it, admin features are inaccessible.
- **Hot reload**: Use `r` in the terminal running `flutter run` for hot reload, `R` for hot restart.
