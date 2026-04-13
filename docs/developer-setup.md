# Developer Setup Guide

Platform-specific setup instructions for building and running Soliplex.

## Prerequisites

- Flutter SDK (stable channel, >=3.27.0)
- Xcode (for iOS/macOS)
- CocoaPods (`gem install cocoapods`)
- Android Studio (for Android)

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run -d macos   # or: -d ios, -d chrome, -d android
```

## Platform Setup

### macOS

#### Code Signing (Required for Keychain)

macOS apps require code signing to access Keychain for secure token storage.
Each developer must configure their own Apple Developer Team ID:

```bash
# 1. Copy the template
cp macos/Runner/Configs/Local.xcconfig.template macos/Runner/Configs/Local.xcconfig

# 2. Edit Local.xcconfig and uncomment/set your Team ID
```

Your `Local.xcconfig` should contain:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
```

**Finding your Team ID:**

1. Go to <https://developer.apple.com/account>
2. Click "Membership details"
3. Copy the 10-character Team ID (e.g., `HYA3HSRUJ8`)

**Verification:**

```bash
flutter build macos --debug
```

If configured correctly, Keychain operations succeed and auth tokens persist
across app restarts.

**Without code signing:** The app runs but Keychain fails silently. Auth works
per-session but tokens don't persist, requiring re-login on each launch.

### iOS

#### Code Signing (Required for Physical Devices)

iOS uses the same xcconfig pattern as macOS:

```bash
# 1. Copy the template
cp ios/Runner/Configs/Local.xcconfig.template ios/Runner/Configs/Local.xcconfig

# 2. Edit Local.xcconfig and uncomment/set your Team ID
```

Your `Local.xcconfig` should contain:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
```

#### Privacy Descriptions (Info.plist)

The `file_picker` dependency links against `Photos.framework`, so iOS requires
`NSPhotoLibraryUsageDescription` in `ios/Runner/Info.plist`. This is already
configured — if you add new plugins that access protected resources (camera,
microphone, location, etc.), add the corresponding `NS*UsageDescription` keys.

#### Simulator vs Device

- **Simulator:** No signing required for debug builds
- **Physical device:** Requires `Local.xcconfig` with valid `DEVELOPMENT_TEAM`

#### Building for TestFlight/App Store

Use Flutter **stable** channel for production builds. Beta/dev channels can
produce binaries that fail App Store validation.

```bash
# Verify you're on stable channel
flutter channel stable
flutter upgrade

# Build release IPA
flutter build ipa --release

# Upload using Transporter app
open -a Transporter build/ios/ipa/soliplex_frontend.ipa
```

### Android

No special signing setup required for debug builds. For release builds, see
[Android signing docs](https://docs.flutter.dev/deployment/android#signing-the-app).

### Web

No special setup required:

```bash
flutter run -d chrome
```

### Linux

```bash
# Install GTK dependencies (Ubuntu/Debian)
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

flutter run -d linux
```

### Windows

Requires Visual Studio with "Desktop development with C++" workload:

```bash
flutter run -d windows
```

## Troubleshooting

### Entitlements require signing

```text
"Runner" has entitlements that require signing with a development certificate
```

**Cause:** Missing `Local.xcconfig` or `DEVELOPMENT_TEAM` not set.

**Fix:** Create `Local.xcconfig` with `DEVELOPMENT_TEAM` as shown above.

### Keychain errors on macOS

```text
OSStatus error -25293
```

**Cause:** Missing or invalid code signing configuration.

**Fix:** Follow the macOS code signing setup above.

### Pod install fails

```bash
# Clean and reinstall
cd ios && pod deintegrate && pod install && cd ..
cd macos && pod deintegrate && pod install && cd ..
```

## Related Files

| File | Purpose |
| ---- | ------- |
| `macos/Runner/Configs/Local.xcconfig.template` | Template for macOS signing |
| `macos/Runner/Configs/Local.xcconfig` | Your macOS signing config (gitignored) |
| `ios/Runner/Configs/Local.xcconfig.template` | Template for iOS signing |
| `ios/Runner/Configs/Local.xcconfig` | Your iOS signing config (gitignored) |
| `ios/Runner/Info.plist` | iOS privacy descriptions and app config |
| `.gitignore` | Excludes `**/Local.xcconfig` |
