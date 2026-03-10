#!/bin/bash
set -e
set -x

# Expected environment variables:
# ANDROID_SDK_ROOT
# TELEGRAM_API_ID
# TELEGRAM_API_HASH

# Ensure gradlew is executable
chmod +x ./gradlew

# Build the APK
./gradlew assembleLatestArm64Release --stacktrace
