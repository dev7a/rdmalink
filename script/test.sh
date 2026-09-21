#!/usr/bin/env bash
# Builds and tests everything: the core package, the CLI, and the app.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/DerivedData"
APP="$BUILD_DIR/Build/Products/Debug/RDMALink.app"

for script in "$ROOT_DIR"/script/*.sh "$ROOT_DIR"/script/release/*.sh; do
  /bin/bash -n "$script"
done

# The release machinery: what publish.sh refuses to publish, which tags
# verify-tag.sh accepts, and what receipt.sh writes. All three run on
# fixtures — no network, no GitHub, no signing identity, about four seconds.
for test in test_release.py test_release_tag.py test_receipt.py; do
  python3 "$ROOT_DIR/script/release/$test"
done

(cd "$ROOT_DIR/Packages/RDMALinkCore" && swift build -Xswiftc -warnings-as-errors && swift test)

# The stage's arithmetic has no test bundle to live in — the app target has
# none — so it is compiled and run on its own. See the script's own header.
"$ROOT_DIR/script/test_stage_math.sh"

# The hub's own copy — the ready row, the port rows and what a note makes of
# a port — is checked the same way, against the Core module built above.
"$ROOT_DIR/script/test_presentation.sh"

# No `|| true` here, ever. It forces the pipeline to exit 0 whatever xcodebuild
# did, and the `test -d` below then passes on the bundle the *last* good build
# left behind — so a compile error printed by grep still ended in "all passed".
# The bundle is removed first for the same reason.
rm -rf "$APP"
LOG="$(mktemp -t rdmalink-xcodebuild)"
trap 'rm -f "$LOG"' EXIT
if ! xcodebuild -project "$ROOT_DIR/RDMALink.xcodeproj" -scheme RDMALink \
  -configuration Debug -derivedDataPath "$BUILD_DIR" build >"$LOG" 2>&1; then
  grep -E "error:|warning:" "$LOG" || tail -40 "$LOG"
  echo "test.sh: the app target failed to build" >&2
  exit 1
fi
grep -E "error:|warning:|BUILD" "$LOG" || true
test -d "$APP"
echo "test.sh: all passed"
