#!/bin/bash
set -e
set -x

# Expected environment variables:
# ANDROID_SDK_ROOT
# TELEGRAM_API_ID
# TELEGRAM_API_HASH

# Ensure gradlew is executable
chmod +x ./gradlew

# Source environment variables if needed (setup_dependencies.sh sets them)
# but Gradle usually handles ANDROID_SDK_ROOT from local.properties

# IMPORTANT: Ensure native dependencies are built before Gradle
# The upstream repo has scripts for this.
# build-ffmpeg.sh and build-vpx.sh should have been run or need to be run.
# Our setup_dependencies.sh script should have handled this if CACHE_HIT was false.
# If CACHE_HIT was true, they should be in the cache.

# Verify if include paths exist
ls -d app/jni/third_party/libvpx/build/latest/arm64-v8a/include || {
    echo "libvpx include missing, building..."
    ./scripts/build-vpx.sh
}

ls -d app/jni/third_party/ffmpeg/build/latest/arm64-v8a/include || {
    echo "ffmpeg include missing, building..."
    ./scripts/build-ffmpeg.sh
}

# Build the APK
./gradlew assembleLatestArm64Release --stacktrace
