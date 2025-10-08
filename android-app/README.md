# Dragon Reboot Android App

Native Android app to trigger server reboots via GCP Storage.

## Features

- 📁 Load service account key files
- 🔥 Trigger reboot on all servers
- ✅ Simple, clean UI
- 🔒 Secure credential handling

## Building

### Prerequisites
- Android SDK
- Gradle

### Build Commands

```bash
# Build debug APK
just build

# Build and install to device
just dev

# Build release APK
just build-release
```

## Usage

1. **Load Service Account Key**: Tap "Load Service Account Key" and select your `dragon-reboot-key.json`
2. **Trigger Reboot**: Tap the red "TRIGGER REBOOT" button

## Setup Requirements

### Option 1: Public Bucket (Simplest)
Make your GCP bucket publicly writable:
```bash
gsutil iam ch allUsers:objectAdmin gs://dragon-reboot-bucket
```

### Option 2: Proper Authentication
Ensure your service account has Storage Object Admin permissions.

## APK Locations

- Debug: `app/build/outputs/apk/debug/app-debug.apk`
- Release: `app/build/outputs/apk/release/app-release.apk`

## Security Notes

- Service account keys are stored in memory only
- No persistent storage of credentials
- Excluded from Android backups