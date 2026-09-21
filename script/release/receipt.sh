#!/usr/bin/env bash
# Writes the two files that travel with a release DMG: SHA256SUMS over the
# final stapled bytes, and release.json, the receipt saying which tag, which
# commit and which notarization produced them.
#
# Modelled on dev7a/lnpctl tools/release/package.sh, which writes the same two
# files at the end of its packaging run. It lives on its own so
# script/release/test_receipt.py can drive it with fixtures — no Xcode, no
# Apple, no network — and so script/package_dmg.sh stays readable.
#
# usage: receipt.sh <assets-dir> <dmg-file-name>
#
# The environment carries what only the packaging run knows:
#   RELEASE_TAG RELEASE_SHA RELEASE_TAG_OBJECT  the validated source
#   VERSION BUILD_NUMBER TEAM_ID BUNDLE_IDENTIFIER
#   NOTARY_APP_JSON NOTARY_IMAGE_JSON  notarytool results, as JSON files
#   MINIMUM_MACOS  optional, defaults to 27.0
#   XCODE_VERSION  optional; read from xcodebuild when unset
set -euo pipefail

ASSETS_DIR="${1:?Assets directory required}"
DMG_NAME="${2:?Disk image file name required}"
: "${RELEASE_TAG:?}" "${RELEASE_SHA:?}" "${RELEASE_TAG_OBJECT:?}"
: "${VERSION:?}" "${BUILD_NUMBER:?}" "${TEAM_ID:?}" "${BUNDLE_IDENTIFIER:?}"
: "${NOTARY_APP_JSON:?}" "${NOTARY_IMAGE_JSON:?}"
MINIMUM_MACOS="${MINIMUM_MACOS:-27.0}"

fail() {
  echo "receipt.sh: $1" >&2
  exit 1
}

[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "not a release tag: $RELEASE_TAG"
[[ "$RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "not a commit hash: $RELEASE_SHA"
[[ "$RELEASE_TAG_OBJECT" =~ ^[0-9a-f]{40}$ ]] ||
  fail "not a tag object hash: $RELEASE_TAG_OBJECT"
# The tag names the version the app carries; nothing else may be published.
[[ "$RELEASE_TAG" == "v$VERSION" ]] ||
  fail "tag $RELEASE_TAG does not match App/Info.plist version $VERSION"
[[ "$DMG_NAME" == "RDMALink-$VERSION.dmg" ]] ||
  fail "unexpected disk image name: $DMG_NAME"
[[ -d "$ASSETS_DIR" ]] || fail "no such directory: $ASSETS_DIR"
[[ -f "$ASSETS_DIR/$DMG_NAME" ]] || fail "no such disk image: $ASSETS_DIR/$DMG_NAME"
[[ -f "$NOTARY_APP_JSON" ]] || fail "no such notary result: $NOTARY_APP_JSON"
[[ -f "$NOTARY_IMAGE_JSON" ]] || fail "no such notary result: $NOTARY_IMAGE_JSON"

if [[ -z "${XCODE_VERSION:-}" ]]; then
  XCODE_VERSION="$(/usr/bin/xcodebuild -version)"
fi

ASSETS_DIR="$ASSETS_DIR" DMG_NAME="$DMG_NAME" MINIMUM_MACOS="$MINIMUM_MACOS" \
XCODE_VERSION="$XCODE_VERSION" /usr/bin/env python3 - <<'PY'
import json
import os
from pathlib import Path


def accepted(path):
    """A notarytool result, refused unless Apple accepted the submission."""
    result = json.loads(Path(path).read_text())
    if result.get("status") != "Accepted":
        raise SystemExit(f"receipt.sh: notarization is {result.get('status')!r}: {path}")
    return result


assets = Path(os.environ["ASSETS_DIR"])
receipt = {
    "tag": os.environ["RELEASE_TAG"],
    "commit": os.environ["RELEASE_SHA"],
    "tag_object": os.environ["RELEASE_TAG_OBJECT"],
    "version": os.environ["VERSION"],
    "build": os.environ["BUILD_NUMBER"],
    "asset": os.environ["DMG_NAME"],
    "architecture": "arm64",
    "minimum_macos": os.environ["MINIMUM_MACOS"],
    "team_id": os.environ["TEAM_ID"],
    "bundle_identifier": os.environ["BUNDLE_IDENTIFIER"],
    "notarization": {
        "app": accepted(os.environ["NOTARY_APP_JSON"]),
        "image": accepted(os.environ["NOTARY_IMAGE_JSON"]),
    },
    "xcode": os.environ["XCODE_VERSION"].strip(),
}
(assets / "release.json").write_text(json.dumps(receipt, indent=2) + "\n")
PY

# Hashed last, and only once the receipt above accepted both notarizations:
# a refused run leaves no half-written pair behind. The bytes hashed are the
# ones that ship — the image after stapling — and the sum file names the
# asset and nothing else.
(cd "$ASSETS_DIR" && /usr/bin/shasum -a 256 "$DMG_NAME" > SHA256SUMS)

echo "receipt: $ASSETS_DIR/SHA256SUMS and $ASSETS_DIR/release.json"
