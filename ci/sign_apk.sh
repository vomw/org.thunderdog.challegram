#!/bin/bash
set -e
set -x

# Expected environment variables:
# ANDROID_SDK_ROOT
# KEYSTORE_PASSWORD
# KEY_ALIAS
# KEY_PASSWORD

APK_PATH=$(find app/build/outputs/apk -name "*.apk" | grep "release" | head -1)
if [ -z "$APK_PATH" ]; then
    echo "No APK found to sign!"
    exit 1
fi
echo "Found APK at: $APK_PATH"

# Defaults if secrets are missing
KS_PASS=${KEYSTORE_PASSWORD:-"android"}
KS_ALIAS=${KEY_ALIAS:-"androiddebugkey"}
K_PASS=${KEY_PASSWORD:-"android"}

$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner sign \
  --ks keystore.jks \
  --ks-pass pass:"$KS_PASS" \
  --ks-key-alias "$KS_ALIAS" \
  --key-pass pass:"$K_PASS" \
  --out app-release-signed.apk \
  "$APK_PATH"

echo "APK signed successfully."

# Verify
$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner verify --verbose app-release-signed.apk
