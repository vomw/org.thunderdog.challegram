#!/bin/bash
set -e
set -x
set -o pipefail

# Expected environment variables:
# ANDROID_SDK_ROOT
# TELEGRAM_API_ID
# TELEGRAM_API_HASH
# GITHUB_REPOSITORY
# CACHE_HIT (true/false)
# HELPERS_DIR (path to the 'ci' scripts)
# KEYSTORE_BASE64 (optional)
# KEYSTORE_PASSWORD (optional)
# KEY_ALIAS (optional)
# KEY_PASSWORD (optional)

# 1. Git Optimizations
git config --global http.postBuffer 1048576000
git config --global core.compression 0
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global core.preloadindex true
git config --global core.fscache true

git config --global url."https://github.com/".insteadOf || true
git config --global url."https://github.com/".insteadOf "git@github.com:" || true

# 2. Make all scripts executable
chmod +x scripts/*.sh scripts/private/*.sh || true
export PATH=$PATH:$(pwd)/scripts

# 3. Patch scripts using the independent Python script
python3 "${HELPERS_DIR}/patch_scripts.py"

# 4. Disable reset.sh to protect potential cache remnants
echo "#!/bin/bash" > scripts/reset.sh
echo "echo 'Skipping reset...'" >> scripts/reset.sh
chmod +x scripts/reset.sh

# 5. Dynamic Submodule Sync
if [ -f .gitmodules ]; then
    echo "Starting dynamic submodule sync..."
    git submodule init
    PATHS=$(git config --file .gitmodules --get-regexp path | awk '{print $2}' | tr -d '\r')
    for sm in $PATHS; do
        echo "Syncing $sm..."
        for i in {1..5}; do
            git submodule update --init --recursive --force --depth 1 "$sm" && break || {
                if [ $i -eq 5 ]; then echo "FAILED to sync $sm"; exit 1; fi
                git submodule deinit -f "$sm" || true
                rm -rf "$sm"
                sleep 20
            }
        done
    done
fi

# 6. Keystore Setup
KS_FILE="debug.keystore"
KS_PROP_FILE="keystore.properties"

if [ -n "$KEYSTORE_BASE64" ]; then
    echo "Decoding provided keystore..."
    echo "$KEYSTORE_BASE64" | base64 --decode > "$KS_FILE"
    KS_PASS=${KEYSTORE_PASSWORD:-"android"}
    KS_ALIAS=${KEY_ALIAS:-"androiddebugkey"}
    K_PASS=${KEY_PASSWORD:-"android"}
else
    echo "No keystore provided, generating one for build testing..."
    keytool -genkey -v -keystore "$KS_FILE" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    KS_PASS="android"
    KS_ALIAS="androiddebugkey"
    K_PASS="android"
fi

cat > "$KS_PROP_FILE" <<EOF
keystore.file=$(pwd)/$KS_FILE
keystore.password=$KS_PASS
key.alias=$KS_ALIAS
key.password=$K_PASS
EOF

# 7. Environment Setup
CPU_COUNT=$(nproc --all)
write_local_properties() {
cat > local.properties <<EOF
sdk.dir=$ANDROID_SDK_ROOT
org.gradle.workers.max=$CPU_COUNT
telegram.api_id=$TELEGRAM_API_ID
telegram.api_hash=$TELEGRAM_API_HASH
app.id=org.thunderdog.challegram
app.name=Telegram X
app.download_url=https://github.com/$GITHUB_REPOSITORY
app.sources_url=https://github.com/$GITHUB_REPOSITORY
keystore.file=$(pwd)/$KS_PROP_FILE
EOF
}

write_local_properties

# 8. Gradle JVM args (performance)
mkdir -p ~/.gradle
cat >> ~/.gradle/gradle.properties <<EOF
org.gradle.jvmargs=-Xmx6g -XX:+UseParallelGC
org.gradle.parallel=true
org.gradle.caching=true
android.useAndroidX=true
EOF

# 9. Build Native / Apply Patches
if [ "$CACHE_HIT" != "true" ]; then
    echo "Cache miss, running full setup..."
    ./scripts/setup.sh --skip-sdk-setup
else
    echo "Cache hit, skipping setup.sh and running patches manually..."
    source ./scripts/set-env.sh --default-sdk-root
    ./scripts/private/patch-opus-impl.sh || true
    ./scripts/private/patch-androidx-media-impl.sh || true
fi

# 10. RE-ENSURE local.properties
echo "Finalizing local.properties..."
write_local_properties
