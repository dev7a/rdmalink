# RDMALink

A macOS utility that prepares Thunderbolt 5 ports for RDMA over Thunderbolt on
the Mac it runs on: it takes a port out of the Thunderbolt Bridge, gives it its
own IPv6 link-local service, keeps an undo note, and can put everything back.
Run it on each Mac of a pair or cluster and pick the ports.

Requires macOS 27 on a Mac with Thunderbolt 5. Not sandboxed; distributed as a
notarized download, never through the App Store.

## Install

1. Download `RDMALink-<version>.dmg` from the
   [releases page](https://github.com/dev7a/rdmalink/releases), open it and
   drag RDMALink to Applications. Each release also carries `SHA256SUMS` and
   `release.json`; to check the download, put it next to `SHA256SUMS` and run
   `shasum -a 256 -c SHA256SUMS`, which must print `OK`. `release.json` says
   which commit and which signed tag the image was built from and records
   Apple's notarization of both the app and the image.
2. Open RDMALink from Applications. The app is signed with a Developer ID and
   notarized, so macOS opens it without any override.
3. When you set up a port, macOS asks for an administrator password. That is
   the system's own prompt for the right to change network settings
   (`system.services.systemconfiguration.network`); RDMALink holds it for one
   burst of writes and never keeps it. Putting a port back asks again.

RDMALink is not sandboxed: it changes the Mac's network settings through the
Authorization API and, for Thunderbolt Bridge membership, a private
SystemConfiguration interface (`SCBridgeInterface*`), neither of which the App
Sandbox allows. It configures only the Mac it runs on; run it on each Mac of
a pair or cluster.

Build from source: `script/test.sh` builds and tests everything with an
ad-hoc signature; `script/package_dmg.sh` builds the signed disk image (see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#packaging)). Releases are cut by
pushing a signed `v<version>` tag, which builds and notarizes on GitHub; see
[script/release/README.md](script/release/README.md).

- Design: [docs/UX_SPEC.md](docs/UX_SPEC.md)
- Architecture and decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
