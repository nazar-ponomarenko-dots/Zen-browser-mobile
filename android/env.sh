#!/usr/bin/env bash
# Shared build environment for the Zen Android builds.
# usage: source android/env.sh   (from any directory)

# The repository root (zen-browser) is derived from this file's location, so no
# developer-specific paths appear anywhere below.
export ZEN_SRC_ROOT="${ZEN_SRC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ZEN_ANDROID_DIR="${ZEN_ANDROID_DIR:-$ZEN_SRC_ROOT/android}"
export ZEN_ENGINE="$ZEN_SRC_ROOT/engine"

export ANDROID_SDK_HOME="${ANDROID_SDK_HOME:-/opt/android-sdk}"
# Composite SDK handed to configure/gradle: the /opt components plus
# cmdline-tools 21.0 and platform 37.1 / build-tools 37.0.0 (required by
# build/moz.configure/android-sdk.configure) in a user-writable directory.
export ZEN_ANDROID_SDK="${ZEN_ANDROID_SDK:-$HOME/.mozbuild/android-sdk-zen}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_SDK_HOME/ndk/29.0.14206865}"
export NDK_TOOLCHAIN_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
export NDK_SYSROOT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

export ZEN_OBJDIR="$ZEN_SRC_ROOT/obj-zen-android"
export ZEN_MOZCONFIG="${ZEN_MOZCONFIG:-$ZEN_ANDROID_DIR/mozconfigs/android.arm64.mozconfig}"

export MOZCONFIG="$ZEN_MOZCONFIG"
export MOZ_OBJDIR="$ZEN_OBJDIR"

export PATH="$HOME/.cargo/bin:$PATH"

# ./mach gradle needs a JDK 17 (AGP requirement); mach bootstrapped one under
# ~/.mozbuild/jdk. Without JAVA_HOME gradle picks up the system JVM instead.
# `ls`-based glob: an unmatched shell glob is a hard error in zsh.
if [[ -z "${JAVA_HOME:-}" ]]; then
  _zen_jdk="$(ls -d "$HOME"/.mozbuild/jdk/jdk-17* 2>/dev/null | head -1)"
  [[ -n "$_zen_jdk" ]] && export JAVA_HOME="$_zen_jdk"
  unset _zen_jdk
fi
