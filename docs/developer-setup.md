# Developer Setup Guide

Platform-specific setup instructions for building and running Soliplex.

## Prerequisites

- Flutter SDK, stable channel — exact version in `.fvmrc` (see below)
- Xcode (for iOS/macOS)
- CocoaPods (`gem install cocoapods`)
- Android Studio (for Android)

### Flutter SDK version

`.fvmrc` at the repository root names the exact SDK that CI builds and tests
with, and it is the only place that version is written:

```json
{
  "flutter": "3.41.9"
}
```

Match it locally. Two ways:

```bash
# With fvm (reads .fvmrc for you; run project commands as `fvm flutter ...`)
fvm use

# Without fvm — install that exact version by whatever means you prefer,
# then confirm it is what your shell resolves
flutter --version
```

fvm is the path of least resistance, not a requirement. `.fvmrc` is a two-line
JSON file that CI parses directly, so any tool or a human can read it.

Do not confuse this with the `environment:` floor in `pubspec.yaml`
(`flutter: ">=3.38.4"`). The floor is the oldest SDK this library promises
consumers; `.fvmrc` is what we develop on today. They are allowed to differ,
and the floor moves only when a dependency forces it.

## Quick Start

```bash
# The ag_ui dependency is fetched from a Git LFS-enabled repo whose
# binary assets we don't use, and one of its LFS objects is missing
# upstream — which aborts the clone during pub get. We need only its
# pure Dart sources (not LFS-tracked), so skip the LFS smudge filter:
export GIT_LFS_SKIP_SMUDGE=1

# Install dependencies
flutter pub get

# Run the app
flutter run -d macos   # or: -d ios, -d chrome, -d android
```

Add `export GIT_LFS_SKIP_SMUDGE=1` to your shell profile (`~/.zshrc`,
`~/.bashrc`) so it persists. CI sets this automatically for its
`pub get` step.

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

Build releases with the exact version in `.fvmrc`. It is a stable-channel
release, so this also keeps beta/dev binaries — which fail App Store
validation — out of a release build.

```bash
# Verify your SDK matches .fvmrc
flutter --version

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
| `.fvmrc` | The Flutter SDK version CI builds with |
