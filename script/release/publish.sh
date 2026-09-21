#!/usr/bin/env bash
# Publishes the notarized disk image to GitHub Releases.
#
# Copied from dev7a/lnpctl tools/release/publish.sh and adapted to this repo's
# asset names. The shape is that repo's: check the downloaded assets against
# their own receipt first, then check that the tag on GitHub is still the tag
# that was verified, create a DRAFT release, upload, verify every asset landed
# with the size it has here, recheck the tag, and only then undraft. A release
# is therefore never visible with missing or stale assets, and a rerun can
# only replace the assets of a draft that was created for this exact source.
set -euo pipefail
: "${RELEASE_TAG_OBJECT:?}" "${RUNNER_TEMP:?}" "${GH_TOKEN:?}" "${GH_REPO:?}" "${RELEASE_TAG:?}" "${RELEASE_SHA:?}"
[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
asset="RDMALink-${RELEASE_TAG#v}.dmg"
python3 - <<'PY'
import hashlib, json, os
from pathlib import Path
p = Path('release-assets')
tag = os.environ['RELEASE_TAG']
name = f'RDMALink-{tag[1:]}.dmg'
assert {f.name for f in p.iterdir()} == {name, 'SHA256SUMS', 'release.json'}
r = json.loads((p / 'release.json').read_text())
assert r['tag'] == tag and r['commit'] == os.environ['RELEASE_SHA']
assert r['tag_object'] == os.environ['RELEASE_TAG_OBJECT']
assert r['version'] == tag[1:] and r['asset'] == name
# Both submissions — the app inside the image and the image itself.
assert r['notarization']['app']['status'] == 'Accepted'
assert r['notarization']['image']['status'] == 'Accepted'
assert (p / 'SHA256SUMS').read_text() == hashlib.sha256((p / name).read_bytes()).hexdigest() + '  ' + name + '\n'
PY
# Require the same verified annotated tag object, not only the same peeled commit.
[[ "$(gh api "repos/$GH_REPO/git/ref/tags/$RELEASE_TAG" --jq .object.sha)" == "$RELEASE_TAG_OBJECT" ]] || exit 1
remote_sha="$(gh api "repos/$GH_REPO/commits/$RELEASE_TAG" --jq .sha)"
[[ "$remote_sha" == "$RELEASE_SHA" ]] || exit 1
# Listing errors must fail rather than being mistaken for an absent release.
existing="$(gh api --paginate "repos/$GH_REPO/releases?per_page=100" --jq ".[] | select(.tag_name == \"$RELEASE_TAG\") | [.id, .draft, .target_commitish] | @tsv")"
if [[ -n "$existing" ]]; then
  IFS=$'\t' read -r _release_id draft target <<< "$existing"
  [[ "$draft" == true && "$target" == "$RELEASE_SHA" ]] || {
    echo 'Refusing to modify an existing published release or a draft for different source.' >&2
    exit 1
  }
else
  gh release create "$RELEASE_TAG" --verify-tag --target "$RELEASE_SHA" --draft \
    --title "RDMALink ${RELEASE_TAG#v}" \
    --notes "A signed and notarized app for Apple silicon Macs on macOS 27 or later. Download the DMG, open it and drag RDMALink to Applications. SHA256SUMS verifies the stapled image; release.json records the source commit and the notarization of both the app and the image."
fi
# A failed upload leaves a draft. Reruns may replace only this validated draft's assets.
gh release upload "$RELEASE_TAG" "release-assets/$asset" release-assets/SHA256SUMS release-assets/release.json --clobber
gh release view "$RELEASE_TAG" --json assets > "$RUNNER_TEMP/remote-assets.json"
python3 - <<'PYASSETS'
import json, os
from pathlib import Path
assets = json.loads((Path(os.environ['RUNNER_TEMP']) / 'remote-assets.json').read_text())['assets']
expected = {f"RDMALink-{os.environ['RELEASE_TAG'][1:]}.dmg", 'SHA256SUMS', 'release.json'}
assert len(assets) == 3 and {a['name'] for a in assets} == expected
for a in assets:
    assert a['size'] == (Path('release-assets') / a['name']).stat().st_size
PYASSETS
# Recheck the moving tag after the upload as well.
[[ "$(gh api "repos/$GH_REPO/git/ref/tags/$RELEASE_TAG" --jq .object.sha)" == "$RELEASE_TAG_OBJECT" ]] || exit 1
[[ "$(gh api "repos/$GH_REPO/commits/$RELEASE_TAG" --jq .sha)" == "$RELEASE_SHA" ]] || exit 1
gh release edit "$RELEASE_TAG" --draft=false
