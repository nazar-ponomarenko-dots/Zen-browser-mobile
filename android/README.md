# Zen под Android

Порт Zen Browser на Android: десктопный Gecko (Firefox `157.0.1`,
`cairo-android`) собирается под Bionic и уезжает в APK как GeckoView-приложение
`app.zen.mobile` — с настоящим zen-хромом (вертикальные вкладки, spaces,
compact mode, welcome-экран), а не как Firefox-for-Android.

Всё в этом репозитории: surfer-патчи к mozilla-central в `src/**`, собственные
модули Zen в `src/zen/**`, сборочный комплект в `android/`. Ветка — `android`.

## Что нужно

| | |
|---|---|
| ОС / место | Linux x86_64, ~25 ГБ (objdir ≈ 6 ГБ на abi, `engine/`, cargo-кэш) |
| Тулчейн Firefox | `python3`, `node`, `cargo`/`rustc` + таргеты `aarch64-linux-android` и `x86_64-linux-android` |
| Android SDK | `cmdline-tools 21.0`, platform и build-tools `37.0.0` (см. `android/env.sh`) |
| Android NDK | `29.0.14206865` — из него берутся clang/ar/strip, системный clang под bionic не линкует |
| JDK | 17, нужен для `./mach gradle` |

## Сборка

```bash
npm ci
npm run init                                  # surfer download + import + bootstrap
bash android/scripts/build-android.sh arm64   # или x86_64 (эмулятор), --no-apk = только Gecko
```

Готовый APK — `android/out/zen-arm64-v8a-debug.apk` (или `zen-x86_64-debug.apk`),
установка: `adb install -r -g android/out/zen-arm64-v8a-debug.apk`.
Полная сборка с нуля — это часы; `./mach build faster` + `stage-package` +
`./mach gradle :zen_app:assembleDebug` для правок JS/CSS — минуты.

Скрипт делает всё в нужном порядке; вот что в нём зашито и почему иначе не собирается:

1. **Локали.** `locales/` копируются в дерево движка скриптом
   (`python3 scripts/update_en_US_packs.py`, на desktop это делает CI), иначе
   `omni.ja` выходит без `browser/zen-*.ftl`.
2. **Java-исходники GeckoView до gradle** (`XPCOMError`, `CrashReport`,
   `GeckoChildProcessServices`): правило генерации лежит в корневом `backend.mk`,
   поэтому нужен `make -C $MOZ_OBJDIR <файл>`, а не `./mach build <target>`.
3. **`AndroidManifest_overlay.xml`** — в debug-сборке несёт 89 `<service>`
   child-процессов; без него APK ставится, но GPU-процесс не поднимается
   (`Unable to start service ...GeckoChildProcessServices$gpu: not found`) и
   рисовать некому.
4. **`./mach build stage-package`** — десктопный `package-manifest.in` требует
   файлы, которых в android-стаге нет; правки идут под `#ifdef MOZ_WIDGET_ANDROID`.
5. **Имя APK** — gradle пишет оба abi в `zen_app-debug.apk`, скрипт копирует с
   abi в имени, иначе x86_64-сборка ставится на arm-устройство «с ошибкой
   совместимости».
6. **`./mach build faster` не трогает C++** — для JS/CSS/ресурсов его хватает,
   правки нативного слоя требуют `./mach build binaries`.
7. **Файлы `src/zen/**` не экспортируются** — они симлинками входят в
   `engine/zen/**` и правятся напрямую; остальное после правки в `engine/`
   выгружается: `npx surfer export-file <путь без engine/>`.

## Отладка на устройстве

GeckoView читает `/data/local/tmp/app.zen.mobile-geckoview-config.yaml`
(ключи `prefs:`, `env:`, `args:`) — так можно ставить prefs и `MOZ_LOG` без
пересборки. Для chrome-JS — RDP-порт GeckoView через `adb forward`.

## Ограничения

- Сборка debug-подписанная: поверх release не ставится, только с удалением.
- Компакт-режим на тач-устройстве — оверлей: свайп от левого края открывает
  панель, тап вне закрывает (`src/zen/compact-mode/ZenAndroidGestures.mjs`).
- Desktop builtin-расширения (`webcompat`, `formautofill`, `pictureinpicture`,
  `newtab`, …) не пакуются: их background-страницы не могут зарегистрировать
  chrome в этой сборке и только держат контент-процесс (~60 МБ PSS каждый).
- `about:newtab` нет — новая вкладка это пустой `about:blank`-таб
  (`zen-empty-tab`), как в самом Zen.
