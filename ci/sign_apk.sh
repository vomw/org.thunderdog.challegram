#!/bin/bash
set -e
set -x

# Expected environment variables:
# ANDROID_SDK_ROOT
# KEYSTORE_PASSWORD
# KEY_ALIAS
# KEY_PASSWORD

# Identify the APK (release only)
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

# Sign using the decoded keystore (it's always debug.keystore in our CI)
$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner sign \
  --ks debug.keystore \
  --ks-pass pass:"$KS_PASS" \
  --ks-key-alias "$KS_ALIAS" \
  --key-pass pass:"$K_PASS" \
  --out app-release-signed.apk \
  "$APK_PATH"

echo "APK signed successfully."

# Verify
$ANDROID_SDK_ROOT/build-tools/36.0.0/apksigner verify --verbose app-release-signed.apk

# Extract APK info for artifact naming
AAPT_PATH="${ANDROID_SDK_ROOT}/build-tools/36.0.0/aapt"
if [ -f "$AAPT_PATH" ]; then
    BADGING=$($AAPT_PATH dump badging app-release-signed.apk)
    PACKAGE_NAME=$(echo "$BADGING" | grep "package" | sed -n "s/.*name='\([^']*\)'.*/\1/p")
    VERSION_NAME=$(echo "$BADGING" | grep "package" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
    VERSION_CODE=$(echo "$BADGING" | grep "package" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")

    # Rename file for more descriptive artifact download
    SAFE_VERSION_NAME=$(echo "$VERSION_NAME" | sed 's/[^a-zA-Z0-9._-]/_/g')
    FINAL_NAME="${PACKAGE_NAME}_v${SAFE_VERSION_NAME}_c${VERSION_CODE}_arm64-v8a.apk"
    cp app-release-signed.apk "$FINAL_NAME"

    echo "package_name=$PACKAGE_NAME" >> "$GITHUB_OUTPUT"
    echo "version_name=$VERSION_NAME" >> "$GITHUB_OUTPUT"
    echo "version_code=$VERSION_CODE" >> "$GITHUB_OUTPUT"
    echo "final_name=$FINAL_NAME" >> "$GITHUB_OUTPUT"
    
    echo "Extracted APK Info: Package=$PACKAGE_NAME, Version=$VERSION_NAME, Code=$VERSION_CODE"
else
    echo "aapt not found, skipping info extraction"
    echo "final_name=app-release-signed.apk" >> "$GITHUB_OUTPUT"
fi
