#!/usr/bin/env bash
# zen-android: полная сборка Gecko под Android (arm64 | x86_64) + APK zen_app.
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

# Zen-локали (zen-*.ftl) живут в $ZEN_SRC_ROOT/locales и в дерево движка
# копируются скриптом — на desktop это делает CI перед сборкой. Без шага
# omni.ja собирается без browser/zen-*.ftl: l10n-ошибки в консоли и
# "uncaught exception" всплески в рантайме. Идемпотентно.
# Скрипт ждёт cwd=корень репозитория (относительные пути locales/, engine/browser/locales).
(cd "$ZEN_SRC_ROOT" && python3 scripts/update_en_US_packs.py) >/dev/null

./mach configure

# gradle-модуль :geckoview компилируется раньше, чем recurse.mk успевает сгенерировать
# эти java-файлы (XPCOMError/CrashReport описаны как GeneratedFile в
# mobile/android/moz.build, а правило лежит в Корневом backend.mk — поэтому make
# зовётся из корня objdir, а не из mobile/android; `./mach build <target>` ругается
# «нет правила»). Без этого :geckoview:compileDebugJavaWithJavac падает с
# "cannot find symbol: class XPCOMError".
GEN_JAVA=(
  mobile/android/geckoview/src/main/java/org/mozilla/geckoview/CrashReport.java
  mobile/android/geckoview/src/main/java/org/mozilla/gecko/util/XPCOMError.java
  mobile/android/geckoview/src/main/java/org/mozilla/gecko/process/GeckoChildProcessServices.java
  # Манифест-оверлей (:geckoview debug/release srcFile в geckoview/build.gradle:141,145)
  # несёт 89 <service> GeckoChildProcessServices — без него APK ставится без
  # child-process-компонентов и `Unable to start service ...$gpu: not found`, то есть
  # GPU-процесс не поднимается и рисовать некому. См. README.md, раздел «Gotchas».
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

# dist/zen/{libxul.so,assets/omni.ja,browser/assets/omni.ja} — см. README.md, раздел «Gotchas».
./mach build stage-package
./mach gradle :zen_app:assembleDebug

APK="$(find "$MOZ_OBJDIR/gradle/build/mobile/android/zen_app/outputs" -name '*.apk' | head -1)"
# gradle пишет оба abi в одно имя zen_app-debug.apk — на планшете их не различить,
# и x86_64-артефакт ставится как «ошибка совместимости». Копия с abi в имени.
ABI="$([[ "$ARCH" == arm64 ]] && echo arm64-v8a || echo x86_64)"
mkdir -p "$HERE/out"
cp -f "$APK" "$HERE/out/zen-$ABI-debug.apk"
echo "[build] APK: $APK"
echo "[build]      android/out/zen-$ABI-debug.apk"
