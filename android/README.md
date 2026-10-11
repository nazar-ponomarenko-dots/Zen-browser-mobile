# Zen on Android

> **Unofficial port.** Built outside the Zen OSS Team, not signed with the
> project key, and not reviewed, tested or supported by the Zen team.

Zen Browser on Android: desktop Gecko (Firefox `157.0.1`, `cairo-android`) is
cross-compiled for Bionic and shipped as the GeckoView application
`app.zen.mobile` — with the real Zen chrome (vertical tabs, spaces, compact
mode, the welcome wizard) rather than a Firefox-for-Android skin.

Everything lives in this repository: surfer patches against mozilla-central
under `src/**`, the Zen modules under `src/zen/**`, and this `android/` build
kit. The branch is `android`.

## Requirements

| | |
|---|---|
| OS / disk | Linux x86_64, ~25 GB (objdir ≈ 6 GB per abi, `engine/`, cargo cache) |
| Firefox toolchain | `python3`, `node`, `cargo`/`rustc` + the `aarch64-linux-android` and `x86_64-linux-android` targets |
| Android SDK | `cmdline-tools 21.0`, platform and build-tools `37.0.0` (see `android/env.sh`) |
| Android NDK | `29.0.14206865` — supplies clang/ar/strip; the system clang cannot link against bionic |
| JDK | 17, needed by `./mach gradle` |

## Building

```bash
npm ci
npm run init                                  # surfer download + import + bootstrap
bash android/scripts/build-android.sh arm64   # or x86_64 (emulator); --no-apk = Gecko only
```

The APK lands at `android/out/zen-arm64-v8a-debug.apk` (or
`zen-x86_64-debug.apk`); install with
`adb install -r -g android/out/zen-arm64-v8a-debug.apk`.
A full build from scratch takes hours; `./mach build faster` + `stage-package` +
`./mach gradle :zen_app:assembleDebug` for JS/CSS changes takes minutes.

The script runs every step in the order it needs. What is baked in there, and
why it does not build otherwise:

### Build notes

1. **Locales.** `locales/` is copied into the engine tree by a script
   (`python3 scripts/update_en_US_packs.py`, done by CI on desktop); without it
   `omni.ja` is packaged without `browser/zen-*.ftl`.
2. **GeckoView Java sources before gradle** (`XPCOMError`, `CrashReport`,
   `GeckoChildProcessServices`): their generation rule lives in the *root*
   `backend.mk`, so they must be built with `make -C $MOZ_OBJDIR <file>`, not
   `./mach build <target>`.
3. **`AndroidManifest_overlay.xml`** — in a debug build it carries the 89
   child-process `<service>` entries; without it the APK installs, the GPU
   process never starts (`Unable to start service
   ...GeckoChildProcessServices$gpu: not found`) and nothing draws.
4. **`./mach build stage-package`** — the desktop `package-manifest.in` lists
   files that do not exist in the android stage; the edits are guarded by
   `#ifdef MOZ_WIDGET_ANDROID`.
5. **APK name** — gradle writes both abis to `zen_app-debug.apk`, so the script
   copies it with the abi in the name; otherwise an x86_64 build "fails on
   compatibility grounds" when installed on an arm device.
6. **`./mach build faster` does not rebuild C++** — it is enough for
   JS/CSS/resource changes, but native edits need `./mach build binaries`.
7. **`src/zen/**` files are not exported** — they are symlinked into
   `engine/zen/**` and edited directly; everything else has to be written back
   after editing it under `engine/`: `npx surfer export-file <path without engine/>`.

## Debugging on a device

GeckoView reads `/data/local/tmp/app.zen.mobile-geckoview-config.yaml` (the
`prefs:`, `env:` and `args:` keys), which sets preferences and `MOZ_LOG`
without a rebuild. For chrome JS, reach the GeckoView RDP port through
`adb forward`.

## Limitations

- The build is debug-signed: it cannot be installed over a release build, only
  after uninstalling it.
- On a touch device compact mode is an overlay: a swipe from the left edge
  reveals the panel, a tap outside it dismisses it
  (`src/zen/compact-mode/ZenAndroidGestures.mjs`).
- The desktop builtin extensions (`webcompat`, `formautofill`,
  `pictureinpicture`, `newtab`, …) are not packaged at all: their background
  pages cannot register chrome in this build and each one only kept a content
  process alive (~60 MB PSS each).
- There is no `about:newtab` — a new tab is an empty `zen-empty-tab`
  (`about:blank`), the same as in Zen itself.
