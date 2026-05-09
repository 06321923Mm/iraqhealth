# Google OAuth Setup — المدار الطبي

## Overview

The app uses Supabase Auth with Google OAuth via the browser flow (PKCE) on
Android and the embedded GoogleSignIn SDK on iOS/macOS.

---

## Android Setup

### 1. SHA-1 Fingerprint

⚠️ **MANUAL ACTION REQUIRED** — Add your keystore SHA-1 to Google Cloud Console.

Get SHA-1 from your debug keystore:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android
```

For release keystore:
```bash
keytool -list -v -keystore android/upload-keystore.jks -alias <your-alias>
```

### 2. Google Cloud Console

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Select your Firebase project
3. Navigate to **APIs & Services → Credentials**
4. Create an **OAuth 2.0 Client ID** of type **Android**:
   - Package name: `net.iraqhealth.app`
   - SHA-1: (from step 1)
5. Create another Client ID of type **Web application**:
   - Authorized redirect URIs:
     - `https://<your-project>.supabase.co/auth/v1/callback`

### 3. Supabase Dashboard

⚠️ **MANUAL ACTION REQUIRED**

1. Go to Supabase Dashboard → **Authentication → Providers → Google**
2. Enable Google provider
3. Set **Client ID**: the Web application client ID from step 2
4. Set **Client Secret**: the client secret from the Web application OAuth client
5. Ensure **Redirect URL** is:
   ```
   net.iraqhealth.app://login-callback/
   ```
   Add this to the **Authorized redirect URIs** in Google Cloud Console too.

### 4. AndroidManifest.xml (already configured)

The intent-filter in `android/app/src/main/AndroidManifest.xml` is already set:
```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="net.iraqhealth.app" android:host="login-callback"/>
</intent-filter>
```

---

## iOS Setup

1. In Google Cloud Console, create a Client ID of type **iOS**:
   - Bundle ID: `net.iraqhealth.app`
2. Copy the Client ID (format: `<numbers>-<hash>.apps.googleusercontent.com`)
3. Set `GOOGLE_IOS_CLIENT_ID` in `assets/env/flutter.env` or via `--dart-define`
4. Add the reversed client ID to `ios/Runner/Info.plist` as a URL scheme:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>com.googleusercontent.apps.<YOUR_CLIENT_ID_REVERSED></string>
       </array>
     </dict>
   </array>
   ```

---

## Common Error Codes

| Code | Meaning | Fix |
|------|---------|-----|
| `sign_in_canceled` | User dismissed the picker | No action (handled silently) |
| `network_error` | No internet connection | Check connectivity |
| `10` (Android) | SHA-1 mismatch | Add correct SHA-1 to Google Cloud Console |
| `12501` | Sign-in cancelled by user | No action |
| `AuthException` | Supabase auth failure | Check redirect URL in Supabase dashboard |

---

## Environment Variables

Store these in `assets/env/flutter.env` (never commit to git):

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
GOOGLE_WEB_CLIENT_ID=63970501606-....apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=63970501606-....apps.googleusercontent.com
OAUTH_REDIRECT_URL=net.iraqhealth.app://login-callback/
```
