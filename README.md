# FreeWave — privacy-first offline mesh messaging

FreeWave is a Flutter prototype for peer-to-peer offline messaging with automatic store-and-forward relaying.

## Important status

This is an advanced development starter, **not a security-audited production app**. The code implements:
- Nearby discovery and connected peer sessions using the `nearby` package.
- X25519 ephemeral key agreement for each outgoing message.
- HKDF-SHA256 key derivation.
- ChaCha20-Poly1305 authenticated encryption of message content.
- Ed25519 signatures over immutable message envelope fields.
- Secure storage for long-term private identity keys.
- Trusted-contact key pinning (manual key comparison required).
- Encrypted packet queue, expiry and hop limit.
- GitHub Actions workflow to build a debug Android APK.

It does not yet implement a full production routing protocol, delivery receipts, anti-replay persistence across all queue states, traffic-analysis resistance, group chats, attachments, key rotation, QR contact exchange, robust Android/iOS background services, or security audit. Do not describe this prototype as fully secure or use it for high-risk communications until independently reviewed, tested, and upgraded with a ratcheting protocol, key rotation, replay protection, and a professional security audit.

## Privacy and trust model

A message is encrypted to the recipient's X25519 public key before it is sent to nearby peers. Relays only see routing metadata (sender/recipient node IDs, message timing, hop count and packet size) and ciphertext; this prototype does not hide traffic patterns. The sender signs the envelope with Ed25519. A recipient must already have a trusted contact record containing the sender's signing public key. Compare contact fingerprints through an independent trusted channel before trusting them; exchanging keys only through an unverified mesh connection is vulnerable to a man-in-the-middle attack.

Transport PIN verification protects the nearby session, but does not establish a person's identity. Do not treat a display name or node ID as proof of identity.

## Platform support

The `nearby` package documents Android, iOS, Windows, macOS and Linux support for connected peer sessions. It uses Wi-Fi/LAN and BLE with hybrid discovery. Sessions are one-to-one; FreeWave performs forwarding in the app layer.

iOS BLE advertising is foreground-only in some modes and operating systems may suspend background apps. Android also imposes background execution restrictions. For initial tests, keep FreeWave open and test on physical devices. No phone app can relay across an ocean without an available chain of radio relays or a separate transport such as satellite/HF radio.

## Setup

Install Flutter stable and Android Studio. Then from the project root:

```bash
flutter doctor
flutter create --platforms=android,ios,windows,macos,linux .
flutter pub get
flutter analyze
flutter test
flutter run
```

The repository contains `lib/` and app configuration, not generated platform projects. Run `flutter create` once to generate them locally; the GitHub workflow also generates Android files automatically for APK builds.

## Android permissions

In `android/app/src/main/AndroidManifest.xml`, add these permissions inside `<manifest>` (before `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

The OS may still prompt for runtime permissions. Review the current `nearby` package platform setup and target SDK requirements before release.

## iOS / macOS setup

Add to `ios/Runner/Info.plist` and `macos/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>FreeWave uses Bluetooth to discover and communicate with nearby devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>FreeWave uses Bluetooth to advertise this device to nearby peers.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>FreeWave uses the local network for offline peer-to-peer messaging.</string>
<key>NSBonjourServices</key>
<array>
  <string>_freewave._tcp</string>
</array>
```

The Bonjour service must match `serviceId: freewave`. Configure macOS network and Bluetooth entitlements as required by the package. iOS release builds and signing require macOS/Xcode and Apple signing credentials.

## Test two or more devices

1. Install the debug APK on two physical Android devices.
2. Enable Bluetooth and Wi-Fi on both. Internet is not required for local peer communication.
3. Open FreeWave and tap **Start FreeWave mesh** on both.
4. When a connection request appears, compare the PIN shown during the request with the other device and accept manually only when it matches.
5. Exchange public identity profiles using the copy-identity control. Verify the public-key fingerprints through a separate trusted channel before saving contacts.
6. Add the recipient node ID and X25519 public key; add and verify the sender's Ed25519 key on the receiver.
7. Send a short test message.
8. Add a third device and test relaying with a topology where the sender and recipient are not directly connected.

The starter currently offers manual public-key profile exchange; it does not yet display QR codes.

## GitHub APK build

1. Create a repository on GitHub.
2. Upload the project files and folders to the repository root.
3. The included workflow generates the Android folder if missing and applies the required Android permissions and minimum SDK setting automatically.
4. Open the repository's **Actions** tab.
5. Enable Actions if prompted.
6. Run **FreeWave Android APK**, or push to `main` / `master`.
7. Wait for the workflow to complete.
8. Open the run and download the `freewave-debug-apk` artifact.
9. Extract the ZIP and install `app-debug.apk` on an Android device.

The workflow builds a debug APK for testing. Do not publish this debug build. For a public release, configure a release signing key in GitHub Actions secrets and build a signed APK or Android App Bundle. Never commit signing keys or passwords to the repository.

## Local Android build

```bash
flutter build apk --debug
```

APK output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

For Windows:

```powershell
flutter run -d windows
flutter build windows --release
```

For iOS, use a Mac with Xcode:

```bash
flutter build ios --release --no-codesign
```
