#!/bin/bash
set -e
set -x
set -o pipefail

# 1. Access remote version.properties to get current config if local is missing or as a source of truth
# Use curl with proxy if provided, otherwise standard curl
CURL_CMD="curl.exe -s"
if [ -n "$SOCKS_PROXY" ]; then
    CURL_CMD="curl.exe --proxy $SOCKS_PROXY -s"
fi

# Try to get latest versions from main branch
REMOTE_VERSION_URL="https://raw.githubusercontent.com/TGX-Android/Telegram-X/main/version.properties"
$CURL_CMD "$REMOTE_VERSION_URL" > remote_version.properties || true

# Use remote as base, then override with local if exists
if [ -f remote_version.properties ]; then
    cp remote_version.properties version.properties
fi
# Note: we already check out the repo, so we should have a local version.properties.
# If for some reason we don't, the above helps.

# 2. Git Optimizations
git config --global http.postBuffer 1048576000
git config --global core.compression 0
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global core.preloadindex true
git config --global core.fscache true

git config --global url."https://github.com/".insteadOf || true
git config --global url."https://github.com/".insteadOf "git@github.com:" || true

# 3. Make all scripts executable
chmod +x scripts/*.sh scripts/private/*.sh || true
export PATH=$PATH:$(pwd)/scripts

# 4. Patch scripts using the independent Python script
python3 "${HELPERS_DIR}/patch_scripts.py"

# 5. Disable reset.sh to protect potential cache remnants
echo "#!/bin/bash" > scripts/reset.sh
echo "echo 'Skipping reset...'" >> scripts/reset.sh
chmod +x scripts/reset.sh

# 6. Dynamic Submodule Sync
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

# 7. Keystore Setup
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

# 8. Environment Setup
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

# 9. Gradle JVM args (performance)
mkdir -p ~/.gradle
cat >> ~/.gradle/gradle.properties <<EOF
org.gradle.jvmargs=-Xmx6g -XX:+UseParallelGC
org.gradle.parallel=true
org.gradle.caching=true
android.useAndroidX=true
EOF

# 10. Build Native / Apply Patches
if [ "$CACHE_HIT" != "true" ]; then
    echo "Cache miss, running full setup..."
    ./scripts/setup.sh --skip-sdk-setup
else
    echo "Cache hit, skipping setup.sh and running patches manually..."
    source ./scripts/set-env.sh --default-sdk-root
    ./scripts/private/patch-opus-impl.sh || true
    ./scripts/private/patch-androidx-media-impl.sh || true
fi

# 11. RE-ENSURE local.properties
echo "Finalizing local.properties..."
write_local_properties
