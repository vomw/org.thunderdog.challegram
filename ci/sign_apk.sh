#!/bin/bash
set -e
set -x

# Expected environment variables:
# ANDROID_SDK_ROOT
# KEYSTORE_PASSWORD
# KEY_ALIAS
# KEY_PASSWORD

# Determine build tools version dynamically from version.properties
BUILD_TOOLS_VERSION=$(grep "version.build_tools" version.properties | cut -d'=' -f2 | tr -d '\r' || echo "36.0.0")
echo "Using Build Tools Version: $BUILD_TOOLS_VERSION"

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

# Sign using the decoded keystore
$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/apksigner sign \
  --ks debug.keystore \
  --ks-pass pass:"$KS_PASS" \
  --ks-key-alias "$KS_ALIAS" \
  --key-pass pass:"$K_PASS" \
  --out app-release-signed.apk \
  "$APK_PATH"

echo "APK signed successfully."

# Verify
$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/apksigner verify --verbose app-release-signed.apk

# Extract APK info for artifact naming using a robust Python script
cat > extract_metadata.py <<EOF
import sys
import subprocess
import re

def get_metadata(apk_path, aapt_path):
    try:
        result = subprocess.run([aapt_path, "dump", "badging", apk_path], capture_output=True, text=True, check=True)
        output = result.stdout
        
        package_match = re.search(r"package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'", output)
        label_match = re.search(r"application-label:'([^']*)'", output)
        
        package_name = package_match.group(1) if package_match else "unavailable"
        version_code = package_match.group(2) if package_match else "unavailable"
        version_name = package_match.group(3) if package_match else "unavailable"
        app_name = label_match.group(1) if label_match else "unavailable"
        
        return app_name, package_name, version_name, version_code
    except Exception as e:
        print(f"Error extracting metadata: {e}", file=sys.stderr)
        return "unavailable", "unavailable", "unavailable", "unavailable"

if __name__ == "__main__":
    apk = sys.argv[1]
    aapt = sys.argv[2]
    app_name, package_name, version_name, version_code = get_metadata(apk, aapt)
    
    # Sanitize names for filenames
    safe_app = re.sub(r'[^a-zA-Z0-9._-]', '_', app_name)
    safe_version = re.sub(r'[^a-zA-Z0-9._-]', '_', version_name)
    
    print(f"app_name={safe_app}")
    print(f"package_name={package_name}")
    print(f"version_name={version_name}")
    print(f"safe_version_name={safe_version}")
    print(f"version_code={version_code}")
EOF

METADATA=$(python3 extract_metadata.py app-release-signed.apk "$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/aapt")

# Parse python output into GITHUB_OUTPUT
while IFS= read -r line; do
    echo "$line" >> "$GITHUB_OUTPUT"
done <<< "$METADATA"

# Source the metadata to use in shell
eval $(echo "$METADATA" | sed 's/=/="/;s/$/"/')

FINAL_NAME="${app_name}_${package_name}_v${safe_version_name}_c${version_code}_arm64-v8a.apk"
cp app-release-signed.apk "$FINAL_NAME"
echo "final_name=$FINAL_NAME" >> "$GITHUB_OUTPUT"

echo "Extracted APK Info: App=$app_name, Package=$package_name, Version=$version_name, Code=$version_code"
