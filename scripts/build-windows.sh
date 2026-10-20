#!/bin/sh
# Optional macOS/Linux cross-build; native Windows release builds use CMake/MSVC.
set -eu
cd "$(dirname "$0")/.."
: "${ZIG:?Set ZIG to the path of an installed Zig compiler (tested with 0.17.0)}"
mkdir -p dist/windows-x64 dist/zig-global-cache dist/zig-local-cache
export ZIG_GLOBAL_CACHE_DIR="$PWD/dist/zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$PWD/dist/zig-local-cache"
"$ZIG" c++ -target x86_64-windows-gnu -std=c++17 -O2 -Wall -Wextra \
  -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN -DNOMINMAX \
  windows/main.cpp windows/app.rc -Iwindows -municode -Wl,--subsystem,windows -static \
  -luser32 -lgdi32 -lshell32 -ladvapi32 -lcomctl32 -ldwmapi -lpsapi -lole32 \
  -o dist/windows-x64/LightSnap.exe
cp windows/README.md dist/windows-x64/README.md
printf 'Built dist/windows-x64/LightSnap.exe (cross-compiled; Windows execution not checked).\n'
