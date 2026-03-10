import os
import re
import sys

def patch_file_regex(path, pattern, replace):
    if not os.path.exists(path):
        print(f"FILE NOT FOUND: {path}")
        return
    with open(path, "r") as f:
        content = f.read()
    new_content = re.sub(pattern, replace, content)
    if new_content != content:
        with open(path, "w") as f:
            f.write(new_content)
        print(f"Patched {path}")
    else:
        print(f"PATTERN NOT MATCHED in {path}")

def main():
    # 1. Fix set-env.sh typo
    patch_file_regex("scripts/set-env.sh", r"ANDROID_SDK_ROOT=$DEFAULT_ANDROID_SDK\b", "ANDROID_SDK_ROOT=$DEFAULT_ANDROID_SDK_ROOT")

    # 2. Force ARM64 Latest build for speed in build-vpx-impl.sh
    patch_file_regex("scripts/private/build-vpx-impl.sh", r"for ABI in [^;]+ ; do", "for ABI in arm64-v8a ; do")
    patch_file_regex("scripts/private/build-vpx-impl.sh", r"for FLAVOR in [^;]+ ; do", "for FLAVOR in latest ; do")

    # 3. Only build arm64 latest for ffmpeg
    ffmpeg_script = "scripts/private/build-ffmpeg-impl.sh"
    if os.path.exists(ffmpeg_script):
        with open(ffmpeg_script, "r") as f:
            lines = f.readlines()
        with open(ffmpeg_script, "w") as f:
            done = False
            for line in lines:
                f.write(line)
                if "build_one" in line and not done and "function" not in line:
                    f.write("exit 0\n")
                    done = True
        print(f"Patched {ffmpeg_script} to stop after first build")

if __name__ == "__main__":
    main()
