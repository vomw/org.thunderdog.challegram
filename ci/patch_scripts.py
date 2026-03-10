import os
import re
import sys

def patch_file_regex(path, pattern, replace, flags=0):
    if not os.path.exists(path):
        print(f"FILE NOT FOUND: {path}")
        return
    with open(path, "r") as f:
        content = f.read()
    new_content = re.sub(pattern, replace, content, flags=flags)
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
    # 1. Fix set-env.sh tput issues (Terminal compatibility)
    set_env_path = "scripts/set-env.sh"
    if os.path.exists(set_env_path):
        with open(set_env_path, "r") as f:
            lines = f.readlines()
        with open(set_env_path, "w") as f:
            for line in lines:
                if "tput" in line:
                    f.write(line.replace('$(tput', '$(tput 2>/dev/null || echo "" #'))
                else:
                    f.write(line)
        print(f"Patched {set_env_path} to handle tput failures")

    # 2. Fix set-env.sh typo
    patch_file_simple("scripts/set-env.sh", "ANDROID_SDK_ROOT=$DEFAULT_ANDROID_SDK", "ANDROID_SDK_ROOT=$DEFAULT_ANDROID_SDK_ROOT")

    # 3. Fix app/jni/CMakeLists.txt binary directory for tgvoip
    # This ensures that static libs are found in tgcalls/ directory instead of tgvoip/
    search_cm = """# tgcalls
if (${ENABLE_TGVOIP})
  add_subdirectory(
    "${PROJECT_SOURCE_DIR}/tgvoip"
  )
endif()"""
    replace_cm = """# tgcalls
if (${ENABLE_TGVOIP})
  add_subdirectory(
    "${PROJECT_SOURCE_DIR}/tgvoip"
    tgcalls
  )
endif()"""
    patch_file_simple("app/jni/CMakeLists.txt", search_cm, replace_cm)

    # 4. Force ARM64 Latest build for speed in build-vpx-impl.sh
    patch_file_regex("scripts/private/build-vpx-impl.sh", r"for ABI in [^;]+ ; do", "for ABI in arm64-v8a ; do")
    patch_file_regex("scripts/private/build-vpx-impl.sh", r"for FLAVOR in [^;]+ ; do", "for FLAVOR in latest ; do")

    # 5. Only build arm64 latest for ffmpeg
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
