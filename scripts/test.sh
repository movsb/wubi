#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" \
  macos/Dictionary.swift macos/Punctuation.swift macos/InputEngine.swift macos/KeyEvent.swift \
  tests/InputEngineTests.swift tests/KeyEventTests.swift tests/main.swift -o build/tests
./build/tests
