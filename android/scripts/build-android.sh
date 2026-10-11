#!/usr/bin/env bash
# Full Android build of Gecko (arm64 | x86_64) + the zen_app APK.
# usage: android/scripts/build-android.sh [arm64|x86_64] [--no-apk]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-arm64}"
NO_APK="${2:-}"
source "$HERE/env.sh"

case "$ARCH" in
  arm64)
    export MOZCONFIG="$HERE/mozconfigs/android.arm64.mozconfig"
    export MOZ_OBJDIR="$ZEN_SRC_ROOT/obj-zen-android"
    ;;
  x86_64)
    export MOZCONFIG="$HERE/mozconfigs/android.x86_64.mozconfig"
    export MOZ_OBJDIR="$ZEN_SRC_ROOT/obj-zen-android-x86_64"
    ;;
  *) echo "arch must be arm64|x86_64" >&2; exit 2 ;;
esac
JOBS="${JOBS:-4}"

cd "$ZEN_ENGINE"

# The Zen locales (zen-*.ftl) live in $ZEN_SRC_ROOT/locales and are copied into
# the engine tree by a script — on desktop CI does this before building. Without
# this step omni.ja is packaged without browser/zen-*.ftl, which shows up as l10n
# errors in the console and "uncaught exception" bursts at runtime. Idempotent.
# The script expects cwd=repository root (relative locales/, engine/browser/locales).
(cd "$ZEN_SRC_ROOT" && python3 scripts/update_en_US_packs.py) >/dev/null

./mach configure

# The :geckoview gradle module compiles before recurse.mk has generated these
# java files: XPCOMError/CrashReport are declared as GeneratedFile in
# mobile/android/moz.build but the rule lives in the root backend.mk, so make has
# to be called from the objdir root rather than from mobile/android (and
# `./mach build <target>` refuses with "no rule"). Without this step
# :geckoview:compileDebugJavaWithJavac fails with
# "cannot find symbol: class XPCOMError".
GEN_JAVA=(
  mobile/android/geckoview/src/main/java/org/mozilla/geckoview/CrashReport.java
  mobile/android/geckoview/src/main/java/org/mozilla/gecko/util/XPCOMError.java
  mobile/android/geckoview/src/main/java/org/mozilla/gecko/process/GeckoChildProcessServices.java
  # The manifest overlay (the :geckoview debug/release srcFile at
  # geckoview/build.gradle:141,145) carries 89 <service> GeckoChildProcessServices
  # entries. Without it the APK installs without the child-process components and
  # the parent logs `Unable to start service ...$gpu: not found`, so no GPU
  # process comes up and nothing renders. See README.md, "Build notes".
  mobile/android/geckoview/src/main/AndroidManifest_overlay.xml
)
mkdir -p "$MOZ_OBJDIR"
for f in "${GEN_JAVA[@]}"; do
  "${MAKE:-make}" -C "$MOZ_OBJDIR" -j"$JOBS" -s "$f" >/dev/null
done
echo "[build] generated geckoview java sources ok"

./mach build -v -j"$JOBS"

if [[ "$NO_APK" == "--no-apk" ]]; then
  exit 0
fi

# dist/zen/{libxul.so,assets/omni.ja,browser/assets/omni.ja} — see README.md,
# "Build notes".
./mach build stage-package
./mach gradle :zen_app:assembleDebug

APK="$(find "$MOZ_OBJDIR/gradle/build/mobile/android/zen_app/outputs" -name '*.apk' | head -1)"
# gradle writes both abis under the same name zen_app-debug.apk, so on the tablet
# they are indistinguishable and the x86_64 artifact installs as a "compatibility
# error". Keep a copy with the abi in the name.
ABI="$([[ "$ARCH" == arm64 ]] && echo arm64-v8a || echo x86_64)"
mkdir -p "$HERE/out"
cp -f "$APK" "$HERE/out/zen-$ABI-debug.apk"
echo "[build] APK: $APK"
echo "[build]      android/out/zen-$ABI-debug.apk"
