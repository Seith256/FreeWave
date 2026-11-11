from pathlib import Path
import re

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit("AndroidManifest.xml not found. Run flutter create first.")

permissions = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
    '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />',
    '<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />',
]

text = manifest.read_text(encoding="utf-8")
missing = [item for item in permissions if item.split('"')[1] not in text]
if missing:
    manifest_open = re.search(r"<manifest\b[^>]*>", text)
    if manifest_open is None:
        raise SystemExit("Could not locate the opening <manifest> tag.")
    close = manifest_open.end()
    text = text[:close] + "\n    " + "\n    ".join(missing) + text[close:]
manifest.write_text(text, encoding="utf-8")

# flutter_secure_storage 11.x requires Android API 23+.
for gradle_file in [Path("android/app/build.gradle"), Path("android/app/build.gradle.kts")]:
    if not gradle_file.exists():
        continue
    gradle = gradle_file.read_text(encoding="utf-8")
    if gradle_file.suffix == ".kts":
        gradle = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", gradle)
    else:
        gradle = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", gradle)
    gradle_file.write_text(gradle, encoding="utf-8")

print("FreeWave Android permissions and minimum SDK configured.")
