# ✅ UPDATED 2026-05-09
# APK Size Optimization — المدار الطبي

## Target: Under 50 MB (per-ABI split APK)

---

## Optimizations Applied

### 1. R8 Minification + Resource Shrinking (already enabled)

In `android/app/build.gradle.kts`:
```kotlin
release {
    isMinifyEnabled = true      // R8 dead-code elimination + obfuscation
    isShrinkResources = true    // Remove unused resources
    proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro",
    )
}
```

### 2. Split-ABI APKs (CI: android-split-apk.yml)

```bash
flutter build apk --release --split-per-abi
```

Produces three smaller APKs instead of one fat APK:
- `app-arm64-v8a-release.apk` — modern 64-bit devices (~25–35 MB)
- `app-armeabi-v7a-release.apk` — older 32-bit devices
- `app-x86_64-release.apk` — emulators / x86 devices

**Google Play** automatically serves the correct split to each device.

### 3. App Bundle (AAB) for Play Store (CI: release.yml)

```bash
flutter build appbundle --release
```

The AAB lets Play Store deliver only the resources/code each device needs,
further reducing download size by ~20–30%.  Use AAB for all Play Store
submissions.

### 4. Dependency Audit

| Package | Status | Notes |
|---------|--------|-------|
| `shimmer` | Keep | Lightweight shimmer effect |
| `dio` | Keep | Used for HTTP requests |
| `firebase_analytics` | Keep | Required for analytics |
| `firebase_crashlytics` | Keep | Required for crash reporting |
| `firebase_messaging` | Keep | FCM push notifications |
| `google_maps_flutter` | Keep | Core map feature |
| `flutter_local_notifications` | ✅ Removed | No usage found in `lib/` — removed 2026-05-09, saves ~2MB |
| `connectivity_plus` | ⚠️ Review | Not yet imported in `lib/` — activated by offline cache implementation |
| `google_sign_in` | Keep | Authentication |

### 5. ProGuard Rules (android/app/proguard-rules.pro)

Added rules for:
- Supabase/Kotlinx Serialization (prevent JSON class stripping)
- Firebase Messaging payload classes
- Firebase Crashlytics (preserve stack traces)
- Flutter Local Notifications

### 6. Image Assets

Ensure `assets/icons/app_icon.png` and `assets/icons/app_icon_foreground.png`
are WebP-optimized.  Use:
```bash
cwebp -q 90 app_icon.png -o app_icon.webp
```
Flutter's launcher icons tool (`flutter_launcher_icons`) already handles
resizing to all required densities.

---

## How to Measure APK Size

```bash
# Size breakdown by feature
flutter build apk --release --analyze-size

# Actual output file sizes
ls -lh build/app/outputs/flutter-apk/

# Split per ABI
flutter build apk --release --split-per-abi
ls -lh build/app/outputs/flutter-apk/*release.apk
```

---

## AAB vs APK

| | APK | AAB |
|-|-----|-----|
| Use for | Direct install / testing | Google Play Store |
| Size | Larger (all ABIs) | Smaller (dynamic delivery) |
| Sideloading | Yes | No (needs Play) |
| Play requirement | Legacy | Required since Aug 2021 |

---

## Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `GOOGLE_SERVICES_JSON` | Contents of `android/app/google-services.json` |
| `MAPS_API_KEY` | Google Maps SDK key |
| `KEYSTORE_BASE64` | Release keystore (base64 encoded) |
| `KEY_PROPERTIES` | Contents of `android/key.properties` |

---

### 4. ABI Filters in build.gradle.kts

Added `ndk { abiFilters }` to `defaultConfig` to explicitly define target ABIs:
- `arm64-v8a` — covers ~95% of active Android devices (2024)
- `armeabi-v7a` — older 32-bit devices
- `x86_64` — Android emulators

This prevents the build system from including unused native libraries, reducing
the fat APK size before split. For Play Store, split-per-ABI in CI achieves
the same result more cleanly.

---

### 5. Dependency Audit Results (audited 2026-05-09)

| Package | Size Impact | Usage | Decision |
|---------|------------|-------|----------|
| `flutter_local_notifications` | ~2MB | **Removed 2026-05-09** | ✅ Removed — saved ~2MB. FCM handles all push display. |
| `connectivity_plus` | ~0.3MB | Offline cache (`lib/core/cache/connectivity_service.dart`) | Keep — required for Task 4 offline detection |
| `google_maps_flutter` | ~8MB | Map screen — essential | Keep |
| `firebase_messaging` | ~1.5MB | Push notifications | Keep |
| `firebase_crashlytics` | ~0.8MB | Crash reporting | Keep |
| `dio` | ~0.5MB | HTTP layer | Keep |
| `shimmer` | ~0.1MB | Loading skeleton | Keep |

---

## Checklist Before Play Store Release

- [ ] `flutter build appbundle --release` completes without errors
- [ ] `flutter build apk --release --split-per-abi` produces 3 APKs all < 50MB
- [ ] `isMinifyEnabled = true` confirmed in build.gradle.kts
- [ ] `isShrinkResources = true` confirmed in build.gradle.kts
- [ ] proguard-rules.pro covers: Google Maps, Supabase, Firebase, flutter_local_notifications
- [ ] `google-services.json` present and matches production Firebase project
- [ ] Release keystore configured in `android/key.properties`
- [ ] Version code incremented in pubspec.yaml before each Play upload
- [ ] AAB tested on physical device via internal testing track before production release
