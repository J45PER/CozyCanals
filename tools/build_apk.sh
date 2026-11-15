#!/usr/bin/env bash
# Builds an Android test APK into builds/CozyCanals.apk.
#
# Needs: Godot 4.5.1 with export templates installed, Java, and the Android
# SDK's platform-tools and build-tools set in Godot's Editor Settings
# (Export > Android). Signed with android/test.keystore, a throwaway test key
# shared by every build so new versions install over old ones.
#
#   GODOT=/path/to/godot tools/build_apk.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/android/test.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android
mkdir -p builds
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release Android builds/CozyCanals.apk
rm -f builds/CozyCanals.apk.idsig
ls -la builds/CozyCanals.apk
