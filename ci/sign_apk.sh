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
        # We need to capture both badging and some extra info to be safe
        result = subprocess.run([aapt_path, "dump", "badging", apk_path], capture_output=True, text=True, check=True)
        output = result.stdout
        
        # Package Info
        package_name = "unavailable"
        version_code = "unavailable"
        version_name = "unavailable"
        
        package_match = re.search(r"^package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'", output, re.MULTILINE)
        if package_match:
            package_name = package_match.group(1)
            version_code = package_match.group(2)
            version_name = package_match.group(3)
        
        # App Label (App Name)
        app_name = "unavailable"
        # Try application-label first
        label_match = re.search(r"^application-label:'([^']*)'", output, re.MULTILINE)
        if label_match:
            app_name = label_match.group(1)
        else:
            # Fallback to application-label-en-US or similar if available
            label_any_match = re.search(r"^application-label-[^:]+:'([^']*)'", output, re.MULTILINE)
            if label_any_match:
                app_name = label_any_match.group(1)
            else:
                # Last resort: use the package name as part of the app name
                app_name = "TelegramX"
        
        return app_name, package_name, version_name, version_code
    except Exception as e:
        print(f"Error extracting metadata: {e}", file=sys.stderr)
        return "unavailable", "unavailable", "unavailable", "unavailable"

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("app_name=unavailable\npackage_name=unavailable\nversion_name=unavailable\nsafe_version_name=unavailable\nversion_code=unavailable")
        sys.exit(0)
        
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

# Source the metadata to use in shell safely
# We only want to evaluate known safe variables
app_name=$(echo "$METADATA" | grep "^app_name=" | cut -d'=' -f2)
package_name=$(echo "$METADATA" | grep "^package_name=" | cut -d'=' -f2)
safe_version_name=$(echo "$METADATA" | grep "^safe_version_name=" | cut -d'=' -f2)
version_code=$(echo "$METADATA" | grep "^version_code=" | cut -d'=' -f2)

FINAL_NAME="${app_name}_${package_name}_v${safe_version_name}_c${version_code}_arm64-v8a.apk"
cp app-release-signed.apk "$FINAL_NAME"
echo "final_name=$FINAL_NAME" >> "$GITHUB_OUTPUT"

echo "Extracted APK Info: App=$app_name, Package=$package_name, Version=$safe_version_name, Code=$version_code"
