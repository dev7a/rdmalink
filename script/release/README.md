# Releasing RDMALink

A release is a signed tag and nothing else: pushing `v<version>` builds,
signs, notarizes, staples and publishes `RDMALink-<version>.dmg` to GitHub
Releases. The event flow, the permissions of each job and every failure path
are in [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md#continuous-integration-and-releases).
This file is the operator's side.

## What is here

| File | What it does |
| --- | --- |
| `verify-tag.sh` | Verifies a tag is annotated and signed by an approved key, in a throwaway keyring |
| `trusted-signers.asc` | The approved public keys, read from `main` and never from the tag |
| `receipt.sh` | Writes `SHA256SUMS` and `release.json` beside a stapled image |
| `publish.sh` | Creates a draft release, uploads, verifies, then makes it visible |
| `test_release.py` | Drives `publish.sh` against a fake `gh`: what must never be published |
| `test_release_tag.py` | Drives `verify-tag.sh` against generated keys and tags |
| `test_receipt.py` | Drives `receipt.sh` against fixtures, with no Xcode and no Apple |

All three tests run in `script/test.sh` and need no network.

These are modelled on [dev7a/lnpctl](https://github.com/dev7a/lnpctl)'s
`tools/release/`, which has run this shape of release before.

## Once, before the first release

Create the `release` environment (**Settings → Environments → New
environment**) and add to it the three secrets and three variables listed in
the architecture document's table. The environment is the gate: the signing
secrets exist only there, and only the `notarize` job runs in it.

The approval keys in `trusted-signers.asc` are exported public keys. To add
or replace a signer, commit the new export **to `main`** — the workflow reads
this file from `refs/remotes/origin/main`, so a tag cannot approve itself.

## Cutting a release

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in
   `App/Info.plist` on `main`, and land it.
2. Sign a tag on that commit:
   `git -c gpg.program=/opt/homebrew/bin/gpg tag -s v<version> -m "RDMALink <version>"`.
   The tag must be annotated, signed by a key in `trusted-signers.asc`, and
   named exactly `v` plus the plist's version.
3. Push the tag: `git push origin v<version>`.
4. Watch the run. `preflight` proves the tag, `notarize` builds and submits to
   Apple (the long job), `publish` uploads to a draft and undrafts it.

If `publish` fails, the release stays a draft and nothing is public. Rerun the
workflow: it rebuilds, and replaces only that draft's assets. Never edit the
assets of a draft by hand — the checks that make the receipt meaningful all
run in `publish.sh`.

## Verifying a published release

```sh
shasum -a 256 -c SHA256SUMS      # the stapled image's bytes
spctl --assess --type open --context context:primary-signature -vv RDMALink-<version>.dmg
```

`release.json` names the commit and tag object the image was built from and
carries both notarization results.
