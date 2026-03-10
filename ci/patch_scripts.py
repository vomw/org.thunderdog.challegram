import os
import re
import sys

def patch_file_regex(path, pattern, replace, count=0):
    if not os.path.exists(path):
        print(f"FILE NOT FOUND: {path}")
        return
    with open(path, "r") as f:
        content = f.read()
    new_content = re.sub(pattern, replace, content, count=count, flags=re.MULTILINE)
    if new_content != content:
        with open(path, "w") as f:
            f.write(new_content)
        print(f"Patched {path}")
    else:
        print(f"PATTERN NOT MATCHED in {path}")

def patch_file_simple(path, search, replace):
    if not os.path.exists(path):
        print(f"FILE NOT FOUND: {path}")
        return
    with open(path, "r") as f:
        content = f.read()
    if search in content:
        with open(path, "w") as f:
            f.write(content.replace(search, replace))
        print(f"Patched {path}")
    else:
        print(f"SEARCH STRING NOT FOUND in {path}")

def main():
    # 1. Fix set-env.sh typo
    patch_file_simple("scripts/set-env.sh", "ANDROID_SDK_ROOT=$DEFAULT_ANDROID_SDK", "ANDROID_SDK_ROOT=$DEFAULT_ANDROID_SDK_ROOT")

    # 2. Fix native linker failure by removing 'tgcalls/' prefix from exclude list
    # The linker flags in tgvoip/CMakeLists.txt incorrectly assume a 'tgcalls' subdirectory for static archives
    tgvoip_cm = "app/jni/tgvoip/CMakeLists.txt"
    if os.path.exists(tgvoip_cm):
        with open(tgvoip_cm, "r") as f:
            content = f.read()
        
        # Remove 'tgcalls/' prefix from paths like 'tgcalls/libusrsctp.a'
        # We target the specific list block
        new_content = content.replace("tgcalls/lib", "lib")
        
        if new_content != content:
            with open(tgvoip_cm, "w") as f:
                f.write(new_content)
            print(f"Patched {tgvoip_cm} to remove 'tgcalls/' prefix from excluded libraries")
        else:
            print(f"Prefix 'tgcalls/' NOT FOUND in {tgvoip_cm}")

    # 3. Force ARM64 Latest build for speed in build-vpx-impl.sh
    patch_file_regex("scripts/private/build-vpx-impl.sh", r"for ABI in [^;]+ ; do", "for ABI in arm64-v8a ; do")
    patch_file_regex("scripts/private/build-vpx-impl.sh", r"for FLAVOR in [^;]+ ; do", "for FLAVOR in latest ; do")

    # 4. Only build arm64 latest for ffmpeg
    ffmpeg_script = "scripts/private/build-ffmpeg-impl.sh"
    if os.path.exists(ffmpeg_script):
        with open(ffmpeg_script, "r") as f:
            lines = f.readlines()
        with open(ffmpeg_script, "w") as f:
            done = False
            for line in lines:
                f.write(line)
                # Insert exit 0 after the first build_one call (which corresponds to arm64-v8a/latest)
                if "build_one" in line and not done and "function" not in line:
                    f.write("exit 0\n")
                    done = True
        print(f"Patched {ffmpeg_script} to stop after first build")

if __name__ == "__main__":
    main()
