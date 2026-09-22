#!/usr/bin/env bash
# Verifies that a release tag is an annotated tag signed by an approved key.
#
# Copied from dev7a/lnpctl tools/release/verify-tag.sh, with the GnuPG binary
# resolved rather than taken from PATH. An older gpg on PATH may not be able to
# read a modern (ed25519, keybox) public key at all, so the candidates below are
# tried in order and GPG_PROGRAM overrides them; on a runner, plain `gpg` is it.
#
# usage: verify-tag.sh <tag> <approved-public-keys.asc>
set -euo pipefail
: "${1:?Release tag required}" "${2:?Approved public key file required}"
[[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$(git cat-file -t "refs/tags/$1")" == tag ]] || exit 1

GPG_PROGRAM="${GPG_PROGRAM:-}"
if [[ -z "$GPG_PROGRAM" ]]; then
  for candidate in /opt/homebrew/bin/gpg gpg; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GPG_PROGRAM="$(command -v "$candidate")"
      break
    fi
  done
fi
[[ -n "$GPG_PROGRAM" ]] || {
  echo 'No gpg found; a release tag cannot be verified without one.' >&2
  exit 1
}

# An isolated keyring prevents the machine's other keys from authorizing a
# release: only the approved keys passed in can make a signature good.
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
chmod 700 "$GNUPGHOME"
"$GPG_PROGRAM" --batch --import "$2"
git -c gpg.format=openpgp -c gpg.program="$GPG_PROGRAM" verify-tag --raw "refs/tags/$1"
