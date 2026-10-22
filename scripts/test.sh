#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" \
  macos/Dictionary.swift macos/Punctuation.swift macos/InputEngine.swift \
  tests/InputEngineTests.swift tests/main.swift -o build/tests
./build/tests
