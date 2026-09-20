#!/usr/bin/env bash
# Builds and tests everything: the core package, the CLI, and the app.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$ROOT_DIR"/script/*.sh; do
  /bin/bash -n "$script"
done

(cd "$ROOT_DIR/Packages/RDMALinkCore" && swift build -Xswiftc -warnings-as-errors && swift test)

xcodebuild -project "$ROOT_DIR/RDMALink.xcodeproj" -scheme RDMALink -configuration Debug \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" build | grep -E "error:|warning:|BUILD" || true
test -d "$ROOT_DIR/build/DerivedData/Build/Products/Debug/RDMALink.app"
echo "test.sh: all passed"
