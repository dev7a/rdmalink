#!/usr/bin/env bash
# Builds the disk image RDMALink ships from a GitHub release.
#
# Release is archived and exported with the Developer ID identity, the
# exported app is verified (Developer ID authority, hardened runtime, secure
# timestamp, empty entitlements, arm64 only), and the app goes into a
# compressed disk image next to an Applications link. The image is signed
# with the same identity and verified again once mounted.
#
# Without --notarize the script stops there: the image is signed, not
# notarized, and Gatekeeper will refuse it on another Mac. With --notarize the
# app is submitted to Apple first and stapled, so it carries its own ticket
# once dragged to Applications; then the image is submitted and stapled too.
# Both submissions use the notarytool Keychain profile named below.
#
# Two things change when the environment says this is a release run, and
# nothing else does:
#
#   * NOTARY_KEY_PATH, APPLE_API_KEY_ID and APPLE_API_ISSUER_ID together make
#     notarytool authenticate with an App Store Connect API key instead of the
#     Keychain profile, which is what a GitHub runner has (dev7a/lnpctl
#     tools/release/package.sh does the same).
#   * RELEASE_TAG, RELEASE_SHA and RELEASE_TAG_OBJECT — the tag the release
#     workflow verified — make the script check that it is building exactly
#     that source, and then write dist/release-assets/ with the image,
#     SHA256SUMS over its stapled bytes and release.json, the receipt.
set -euo pipefail

NOTARIZE=0
case "${1:-}" in
  "") ;;
  --notarize) NOTARIZE=1 ;;
  *)
    echo "usage: $0 [--notarize]" >&2
    exit 2
    ;;
esac
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [--notarize]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$ROOT_DIR/build/DerivedData-package"
TEAM_ID=BV5XC39R5P
BUNDLE_IDENTIFIER=com.dev7a.RDMALink
# A notarytool Keychain profile created once with
# `xcrun notarytool store-credentials rdmalink …`; the GitHub release path
# authenticates with the App Store Connect API key instead and never reads it.
NOTARY_PROFILE="${NOTARY_PROFILE:-rdmalink}"
WORK_DIR="$(/usr/bin/mktemp -d /private/tmp/rdmalink-dmg.XXXXXX)"
ARCHIVE_PATH="$WORK_DIR/RDMALink.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
EXPORT_OPTIONS="$WORK_DIR/ExportOptions.plist"
MOUNT_POINT="$WORK_DIR/mount"
IMAGE_ATTACHED=0
ATTACHED_DEVICE=""

cleanup() {
  local result=$?
  trap - EXIT INT TERM
  # The device name is known only once the attach plist has been parsed;
  # until then the image is ejected by its mount point.
  if [[ -n "$ATTACHED_DEVICE" ]]; then
    /usr/sbin/diskutil eject "$ATTACHED_DEVICE" >/dev/null 2>&1 ||
      echo "could not eject $ATTACHED_DEVICE; run: diskutil eject $ATTACHED_DEVICE" >&2
  elif (( IMAGE_ATTACHED )); then
    /usr/sbin/diskutil eject "$MOUNT_POINT" >/dev/null 2>&1 ||
      echo "could not eject $MOUNT_POINT; run: diskutil eject $MOUNT_POINT" >&2
  fi
  # Housekeeping must not replace the run's own exit status.
  case "$WORK_DIR" in
    /private/tmp/rdmalink-dmg.*)
      [[ ! -e "$WORK_DIR" ]] || /bin/rm -r "$WORK_DIR" 2>/dev/null ||
        echo "could not remove $WORK_DIR; remove it by hand" >&2
      ;;
    *)
      echo "refusing to remove unexpected work path: $WORK_DIR" >&2
      result=1
      ;;
  esac
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

# --- signing identity ------------------------------------------------------
# Exactly one Developer ID Application identity for the team must be in the
# login Keychain. Its SHA-1 is what the archive, the export and the image's
# codesign all get, so a same-named identity from another Keychain can never
# be picked up by accident; the post-export checks below assert the authority
# and the team on top of that.
IDENTITY_LINES="$(/usr/bin/security find-identity -v -p codesigning |
  /usr/bin/grep -F "\"Developer ID Application:" |
  /usr/bin/grep -F "($TEAM_ID)\"" || :)"
IDENTITY_COUNT="$(printf '%s\n' "$IDENTITY_LINES" |
  /usr/bin/awk 'NF { n++ } END { print n + 0 }')"
if (( IDENTITY_COUNT == 0 )); then
  fail "No valid Developer ID Application identity for team $TEAM_ID is in the Keychain (on a runner: the imported .p12 is missing or the temporary keychain is not in the search list)." 3
fi
if (( IDENTITY_COUNT > 1 )); then
  fail "More than one Developer ID Application identity for team $TEAM_ID is in the Keychain; remove the stale one." 3
fi
IDENTITY_HASH="$(printf '%s\n' "$IDENTITY_LINES" |
  /usr/bin/sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) .*/\1/p')"
[[ "$IDENTITY_HASH" =~ ^[0-9A-F]{40}$ ]] ||
  fail "Could not read the Developer ID identity hash from: $IDENTITY_LINES" 3

# --- version from the source plist ----------------------------------------
SOURCE_PLIST="$ROOT_DIR/App/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_PLIST")"
for value in "$VERSION" "$BUILD_NUMBER"; do
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] ||
    fail "App/Info.plist has a missing or unsafe version value: '$value'" 2
done

MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$SOURCE_PLIST")"
[[ "$MINIMUM_SYSTEM_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] ||
  fail "App/Info.plist has a missing or unsafe LSMinimumSystemVersion: '$MINIMUM_SYSTEM_VERSION'" 2

# --- notarytool credentials ------------------------------------------------
# A Keychain profile on a Mac someone is sitting at; an App Store Connect API
# key on a runner, where there is no Keychain profile to store. All three key
# variables must arrive together: a partial set would otherwise fall back to
# the profile and sign a release with whatever credentials the machine holds.
NOTARY_CREDENTIALS=(--keychain-profile "$NOTARY_PROFILE")
NOTARY_KEY_SET=0
for value in "${NOTARY_KEY_PATH:-}" "${APPLE_API_KEY_ID:-}" "${APPLE_API_ISSUER_ID:-}"; do
  [[ -z "$value" ]] || NOTARY_KEY_SET=$((NOTARY_KEY_SET + 1))
done
if (( NOTARY_KEY_SET == 3 )); then
  NOTARY_CREDENTIALS=(
    --key "$NOTARY_KEY_PATH"
    --key-id "$APPLE_API_KEY_ID"
    --issuer "$APPLE_API_ISSUER_ID"
  )
elif (( NOTARY_KEY_SET > 0 )); then
  fail "Set NOTARY_KEY_PATH, APPLE_API_KEY_ID and APPLE_API_ISSUER_ID together, or none of them." 2
fi

# The team is pinned in this script; a workflow variable may only agree with it.
if [[ -n "${APPLE_TEAM_ID:-}" && "${APPLE_TEAM_ID:-}" != "$TEAM_ID" ]]; then
  fail "APPLE_TEAM_ID is '$APPLE_TEAM_ID' but this app is signed by team $TEAM_ID." 2
fi

# --- release source (release runs only) ------------------------------------
# The workflow has already verified the signed tag, that its commit is an
# ancestor of main, and that the push was for that commit; what is checked
# here is that this working tree is that commit and carries that version.
RELEASE_MODE=0
if [[ -n "${RELEASE_TAG:-}${RELEASE_SHA:-}${RELEASE_TAG_OBJECT:-}" ]]; then
  : "${RELEASE_TAG:?Set RELEASE_TAG, RELEASE_SHA and RELEASE_TAG_OBJECT together}"
  : "${RELEASE_SHA:?Set RELEASE_TAG, RELEASE_SHA and RELEASE_TAG_OBJECT together}"
  : "${RELEASE_TAG_OBJECT:?Set RELEASE_TAG, RELEASE_SHA and RELEASE_TAG_OBJECT together}"
  RELEASE_MODE=1
  (( NOTARIZE )) ||
    fail "A release run must notarize: pass --notarize." 2
  [[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "Not a release tag: $RELEASE_TAG" 2
  [[ "$RELEASE_TAG" == "v$VERSION" ]] ||
    fail "Tag $RELEASE_TAG does not name App/Info.plist's version $VERSION." 2
  [[ "$RELEASE_TAG_OBJECT" =~ ^[0-9a-f]{40}$ ]] ||
    fail "Not a tag object hash: $RELEASE_TAG_OBJECT" 2
  HEAD_SHA="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)"
  [[ "$HEAD_SHA" == "$RELEASE_SHA" ]] ||
    fail "HEAD is $HEAD_SHA but the release is for $RELEASE_SHA." 2
fi

# --- notary credentials work (--notarize only) -----------------------------
# Checked before the two-minute build so missing credentials fail at once.
if (( NOTARIZE )); then
  if (( NOTARY_KEY_SET == 3 )); then
    [[ -s "$NOTARY_KEY_PATH" ]] ||
      fail "No App Store Connect API key at NOTARY_KEY_PATH ('$NOTARY_KEY_PATH')." 3
  else
    /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
      fail "No notarytool Keychain profile named '$NOTARY_PROFILE'. Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id $TEAM_ID" 3
  fi
fi

# --- archive and export ----------------------------------------------------
# macOS 27 runs on Apple silicon only, so the archive is arm64 only; a
# universal binary would carry a slice no supported Mac can run.
/usr/bin/xcodebuild \
  -project "$ROOT_DIR/RDMALink.xcodeproj" \
  -scheme RDMALink \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY_HASH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

/usr/bin/plutil -create xml1 "$EXPORT_OPTIONS"
/usr/bin/plutil -insert method -string developer-id "$EXPORT_OPTIONS"
/usr/bin/plutil -insert destination -string export "$EXPORT_OPTIONS"
/usr/bin/plutil -insert signingStyle -string manual "$EXPORT_OPTIONS"
/usr/bin/plutil -insert signingCertificate -string "$IDENTITY_HASH" "$EXPORT_OPTIONS"
/usr/bin/plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
/usr/bin/plutil -insert manageAppVersionAndBuildNumber -bool false "$EXPORT_OPTIONS"

# The export signs with a secure timestamp, which needs Apple's timestamp
# server; a transient failure there is the one error worth retrying.
EXPORT_ATTEMPT=1
EXPORT_ATTEMPT_LIMIT=5
while :; do
  EXPORT_LOG="$WORK_DIR/export-attempt-$EXPORT_ATTEMPT.log"
  if /usr/bin/xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" 2>&1 | /usr/bin/tee "$EXPORT_LOG"; then
    break
  fi
  # Xcode reports the outage as "A timestamp was expected but was not found";
  # codesign's own wording is "The timestamp service is not available"
  # (errSecCSTimestampServiceNotAvailable). Anything else is not transient.
  /usr/bin/grep -Eqi \
    "timestamp (service )?(is )?(not (available|found)|was expected)|errSecCSTimestamp" \
    "$EXPORT_LOG" ||
    fail "Developer ID export failed; see the log above."
  (( EXPORT_ATTEMPT < EXPORT_ATTEMPT_LIMIT )) ||
    fail "Developer ID export could not get a secure timestamp after $EXPORT_ATTEMPT attempts."
  echo "Secure timestamp failed; retrying the export ($EXPORT_ATTEMPT/$EXPORT_ATTEMPT_LIMIT)." >&2
  [[ ! -e "$EXPORT_PATH" ]] || /bin/rm -r "$EXPORT_PATH"
  EXPORT_ATTEMPT=$((EXPORT_ATTEMPT + 1))
  /bin/sleep 2
done

APP_BUNDLE="$EXPORT_PATH/RDMALink.app"
[[ -d "$APP_BUNDLE" ]] || fail "Developer ID export did not produce RDMALink.app."

# --- verify the exported app ----------------------------------------------
require_developer_id_signature() {
  local component="$1"
  local details
  /usr/bin/codesign --verify --strict --all-architectures --verbose=2 "$component"
  details="$(/usr/bin/codesign -dv --verbose=4 "$component" 2>&1)"
  printf '%s\n' "$details"
  [[ "$details" == *"Authority=Developer ID Application:"* &&
     "$details" == *"TeamIdentifier=$TEAM_ID"* ]] ||
    fail "Not signed with the team's Developer ID Application identity: $component"
  [[ "$details" == *"Timestamp="* ]] ||
    fail "No secure timestamp in the signature: $component"
}

require_developer_id_signature "$APP_BUNDLE"
APP_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
# The hardened runtime is bit 0x10000 of the CodeDirectory flags.
APP_CD_FLAGS="$(printf '%s\n' "$APP_DETAILS" |
  /usr/bin/sed -n 's/^CodeDirectory .*flags=0x\([0-9a-fA-F]*\).*/\1/p')"
[[ "$APP_CD_FLAGS" =~ ^[0-9a-fA-F]+$ ]] ||
  fail "Could not read the CodeDirectory flags of the exported app."
(( 0x$APP_CD_FLAGS & 0x10000 )) ||
  fail "The exported app does not use the hardened runtime (flags=0x$APP_CD_FLAGS)."
/usr/bin/codesign --verify --strict --deep --all-architectures --verbose=2 "$APP_BUNDLE"

EXPORTED_PLIST="$APP_BUNDLE/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXPORTED_PLIST")" == "$BUNDLE_IDENTIFIER" ]] ||
  fail "The exported app has the wrong bundle identifier."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXPORTED_PLIST")" == "$VERSION" &&
   "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXPORTED_PLIST")" == "$BUILD_NUMBER" ]] ||
  fail "The exported app's version differs from App/Info.plist."

# The app asks for nothing: the SystemConfiguration SPI is reached with dlsym
# and the Authorization API needs no entitlement. Anything else in the signed
# entitlements (get-task-allow above all) is a build mistake.
ENTITLEMENTS_PLIST="$WORK_DIR/entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" >"$ENTITLEMENTS_PLIST" 2>/dev/null ||
  fail "Could not read the signed entitlements."
if [[ -s "$ENTITLEMENTS_PLIST" ]]; then
  /usr/bin/plutil -lint "$ENTITLEMENTS_PLIST" >/dev/null ||
    fail "The signed entitlements are not a property list."
  ENTITLEMENTS_JSON="$(/usr/bin/plutil -convert json -o - "$ENTITLEMENTS_PLIST")"
  [[ "$ENTITLEMENTS_JSON" == "{}" ]] ||
    fail "The exported app carries entitlements it must not: $ENTITLEMENTS_JSON"
fi
echo "entitlements: none (empty set)"

# Every Mach-O file in the bundle is arm64 only and validly signed.
MACHO_COUNT=0
while IFS= read -r -d '' candidate; do
  [[ "$(LC_ALL=C /usr/bin/file -b "$candidate")" == *"Mach-O"* ]] || continue
  MACHO_COUNT=$((MACHO_COUNT + 1))
  ARCHITECTURES="$(/usr/bin/lipo -archs "$candidate")"
  [[ "$ARCHITECTURES" == arm64 ]] ||
    fail "Not arm64 only ('$ARCHITECTURES'): $candidate"
  /usr/bin/codesign --verify --strict --all-architectures "$candidate" ||
    fail "Unsigned or invalid Mach-O file: $candidate"
done < <(/usr/bin/find "$APP_BUNDLE" -type f -print0)
(( MACHO_COUNT > 0 )) || fail "The exported app contains no Mach-O file."
echo "arm64 only: $MACHO_COUNT Mach-O file(s)"
APP_CDHASH="$(printf '%s\n' "$APP_DETAILS" | /usr/bin/awk -F= '/^CDHash=/ { print $2 }')"
[[ -n "$APP_CDHASH" ]] || fail "Could not read the app's CDHash."

# --- notarize the app (--notarize only) ------------------------------------
# The app is notarized on its own and stapled before it goes into the image,
# so the copy the person drags to Applications carries its ticket and opens
# offline. Apple dedupes submissions by content: rerunning is safe.
# NOTARY_RESULT_JSON is where the accepted submission's own words are left,
# for the release receipt to quote.
NOTARY_RESULT_JSON=""
NOTARY_APP_JSON=""
NOTARY_IMAGE_JSON=""
notarize() {
  local artefact="$1"
  local artefact_name submit_plist submission_id submission_status notary_log
  artefact_name="$(/usr/bin/basename "$artefact")"
  submit_plist="$WORK_DIR/notary-$artefact_name.plist"
  /usr/bin/xcrun notarytool submit "$artefact" \
    "${NOTARY_CREDENTIALS[@]}" \
    --wait --output-format plist >"$submit_plist"
  submission_id="$(/usr/bin/plutil -extract id raw -o - "$submit_plist")"
  submission_status="$(/usr/bin/plutil -extract status raw -o - "$submit_plist")"
  if [[ "$submission_status" != "Accepted" ]]; then
    /bin/mkdir -p "$DIST_DIR"
    notary_log="$DIST_DIR/notary-$submission_id.json"
    /usr/bin/xcrun notarytool log "$submission_id" \
      "${NOTARY_CREDENTIALS[@]}" "$notary_log" ||
      echo "could not fetch the notary log for $submission_id" >&2
    fail "Notarization of $artefact_name ended as $submission_status (submission $submission_id); see $notary_log"
  fi
  NOTARY_RESULT_JSON="$WORK_DIR/notary-$artefact_name.json"
  /usr/bin/plutil -convert json -o "$NOTARY_RESULT_JSON" "$submit_plist"
  echo "notarization accepted: $artefact_name (submission $submission_id)"
}

if (( NOTARIZE )); then
  APP_ZIP="$WORK_DIR/RDMALink.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
  notarize "$APP_ZIP"
  NOTARY_APP_JSON="$NOTARY_RESULT_JSON"
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/bin/xcrun stapler validate "$APP_BUNDLE"
fi

# --- disk image ------------------------------------------------------------
PAYLOAD="$WORK_DIR/RDMALink-payload.noindex"
TEMP_DMG="$WORK_DIR/RDMALink-$VERSION.dmg"
/bin/mkdir "$PAYLOAD" "$MOUNT_POINT"
/usr/bin/ditto "$APP_BUNDLE" "$PAYLOAD/RDMALink.app"
/bin/ln -s /Applications "$PAYLOAD/Applications"
/usr/bin/hdiutil create \
  -srcfolder "$PAYLOAD" \
  -volname RDMALink \
  -format UDZO \
  -quiet \
  "$TEMP_DMG"
/usr/bin/hdiutil verify -quiet "$TEMP_DMG"
echo "hdiutil verify: ok"

/usr/bin/codesign --force --timestamp --sign "$IDENTITY_HASH" "$TEMP_DMG"
require_developer_id_signature "$TEMP_DMG"

# What is on the image is what was verified above: same code hash, and the
# Applications link is there.
IMAGE_ATTACHED=1
/usr/sbin/diskutil image attach \
  --readOnly \
  --mountOptions nobrowse \
  --mountPoint "$MOUNT_POINT" \
  --plist \
  "$TEMP_DMG" >"$WORK_DIR/attach.plist"
ATTACHED_DEVICE="$(/usr/bin/plutil -extract \
  system-entities.0.dev-entry raw -o - "$WORK_DIR/attach.plist")"
[[ "$ATTACHED_DEVICE" =~ ^disk[0-9]+$ ]] ||
  fail "Disk image attached as an unexpected device: $ATTACHED_DEVICE"
MOUNTED_APP="$MOUNT_POINT/RDMALink.app"
[[ -L "$MOUNT_POINT/Applications" &&
   "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == /Applications ]] ||
  fail "The disk image is missing the Applications link."
/usr/bin/codesign --verify --strict --deep --all-architectures --verbose=2 "$MOUNTED_APP"
MOUNTED_CDHASH="$(/usr/bin/codesign -dv --verbose=4 "$MOUNTED_APP" 2>&1 |
  /usr/bin/awk -F= '/^CDHash=/ { print $2 }')"
[[ "$MOUNTED_CDHASH" == "$APP_CDHASH" ]] ||
  fail "The app on the disk image does not match the exported app."
/usr/sbin/diskutil eject "$ATTACHED_DEVICE" >/dev/null
ATTACHED_DEVICE=""
IMAGE_ATTACHED=0

# --- notarize the image (--notarize only) ----------------------------------
if (( NOTARIZE )); then
  notarize "$TEMP_DMG"
  NOTARY_IMAGE_JSON="$NOTARY_RESULT_JSON"
  /usr/bin/xcrun stapler staple "$TEMP_DMG"
  /usr/bin/xcrun stapler validate "$TEMP_DMG"
  DMG_ASSESSMENT="$(/usr/sbin/spctl --assess --type open \
    --context context:primary-signature -vv "$TEMP_DMG" 2>&1)" ||
    fail "Gatekeeper rejected the stapled disk image: $DMG_ASSESSMENT"
  [[ "$DMG_ASSESSMENT" == *"source=Notarized Developer ID"* ]] ||
    fail "Gatekeeper did not report a notarized disk image: $DMG_ASSESSMENT"
  APP_ASSESSMENT="$(/usr/sbin/spctl --assess --type execute -vv "$APP_BUNDLE" 2>&1)" ||
    fail "Gatekeeper rejected the stapled app: $APP_ASSESSMENT"
  [[ "$APP_ASSESSMENT" == *"source=Notarized Developer ID"* ]] ||
    fail "Gatekeeper did not report a notarized app: $APP_ASSESSMENT"
  printf '%s\n%s\n' "$DMG_ASSESSMENT" "$APP_ASSESSMENT"
fi

# --- publish to dist/ ------------------------------------------------------
# dist/ holds build products only; an image from an earlier run is replaced.
# The name says whether the image is notarized, so an unnotarized image can
# never be mistaken for the release one or overwrite it.
/bin/mkdir -p "$DIST_DIR"
if (( NOTARIZE )); then
  OUTPUT_DMG="$DIST_DIR/RDMALink-$VERSION.dmg"
else
  OUTPUT_DMG="$DIST_DIR/RDMALink-$VERSION-unnotarized.dmg"
fi
[[ ! -e "$OUTPUT_DMG" ]] || /bin/rm "$OUTPUT_DMG"
/bin/mv "$TEMP_DMG" "$OUTPUT_DMG"
/usr/bin/codesign --verify --verbose=2 "$OUTPUT_DMG"

# --- release assets (release runs only) ------------------------------------
# What the workflow uploads: the image the release ships, the sum over its
# final stapled bytes and the receipt that says where it came from. The
# directory is rebuilt from scratch so no file from an earlier run can ride
# along (dev7a/lnpctl builds its assets directory the same way).
if (( RELEASE_MODE )); then
  ASSETS_DIR="$DIST_DIR/release-assets"
  [[ ! -e "$ASSETS_DIR" ]] || /bin/rm -r "$ASSETS_DIR"
  /bin/mkdir -p "$ASSETS_DIR"
  /bin/cp "$OUTPUT_DMG" "$ASSETS_DIR/RDMALink-$VERSION.dmg"
  # `env` rather than an assignment prefix: the prefix would hide the values
  # this command line itself reads (shellcheck SC2097).
  /usr/bin/env \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    TEAM_ID="$TEAM_ID" \
    BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
    MINIMUM_MACOS="$MINIMUM_SYSTEM_VERSION" \
    NOTARY_APP_JSON="$NOTARY_APP_JSON" \
    NOTARY_IMAGE_JSON="$NOTARY_IMAGE_JSON" \
    "$ROOT_DIR/script/release/receipt.sh" "$ASSETS_DIR" "RDMALink-$VERSION.dmg"
fi

DMG_SIZE="$(/usr/bin/stat -f %z "$OUTPUT_DMG")"
DMG_SHA256="$(/usr/bin/shasum -a 256 "$OUTPUT_DMG" | /usr/bin/awk '{ print $1 }')"
printf 'created %s (%s bytes)\n' "$OUTPUT_DMG" "$DMG_SIZE"
printf 'app CDHash %s\n' "$APP_CDHASH"
printf 'DMG SHA-256 %s\n' "$DMG_SHA256"
if (( NOTARIZE )); then
  printf 'The app and the disk image are notarized and stapled.\n'
else
  printf 'The disk image is signed but NOT notarized; Gatekeeper will refuse it on other Macs.\n'
  printf 'To notarize and staple the app and the image, run:\n'
  printf '  %s --notarize\n' "$ROOT_DIR/script/package_dmg.sh"
  printf 'It rebuilds the same image and then, for the app (zipped with ditto -c -k --keepParent,\n'
  printf 'since notarytool takes no .app directory) and for the image:\n'
  printf '  xcrun notarytool submit <RDMALink.zip|RDMALink-%s.dmg> --keychain-profile %s --wait\n' "$VERSION" "$NOTARY_PROFILE"
  printf '  xcrun stapler staple <RDMALink.app|RDMALink-%s.dmg>\n' "$VERSION"
  printf 'and writes dist/RDMALink-%s.dmg.\n' "$VERSION"
fi
