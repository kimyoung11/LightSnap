#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/ModuleCache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" \
  Sources/LightSnap/WindowActions.swift Sources/LightSnap/LoginItem.swift Sources/LightSnap/Layout.swift Sources/LightSnap/Placement.swift Sources/LightSnap/RestoreHistory.swift Sources/LightSnap/Hotkeys.swift Sources/LightSnap/Diagnostics.swift Sources/LightSnap/SnapEngine.swift Tests/main.swift \
  -o .build/layout-tests
.build/layout-tests
