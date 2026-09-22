# RDMALink

A macOS utility that prepares Thunderbolt 5 ports for RDMA over Thunderbolt on
the Mac it runs on. It shows you a 3D model of your machine with every
receptacle where it really is, walks you through a three-step assistant —
choose a port, read exactly what will change, watch it happen — and leaves the
port out of the Thunderbolt Bridge with an IPv6 link-local service of its own,
ready to carry RDMA to another Mac. It keeps an undo note for every port it
touches, so it can put everything back the way it found it. It configures only
the Mac it is running on; run it on each Mac of a pair or cluster and pick the
ports.

## What it changes, and what that means for you

RDMALink is a network-configuration tool. Before you run it, know this much:

- **It changes your network settings.** It removes a Thunderbolt port from
  every bridge it is in and creates a network service for that port with IPv4
  off and IPv6 link-local only. It never creates or deletes a bridge, and it
  never touches a port you did not pick.
- **It uses a private macOS interface.** Bridge membership has no public API,
  so RDMALink resolves the undocumented `SCBridgeInterface*` symbols with
  `dlsym` before it uses them. If one is missing on your system, the change
  stops and is rolled back, and the app explains the manual route through
  System Settings instead of guessing.
- **It asks for an administrator password, once per change.** That is macOS's
  own prompt for the right to change network settings
  (`system.services.systemconfiguration.network`). RDMALink holds that right
  for one burst of writes and then drops it. Putting a port back asks again.
- **It keeps undo notes on your disk**, one small JSON file per port, in
  `~/Library/Application Support/RDMALink`. Those notes are what makes
  "put it back" possible. They are safe to back up and safe to leave alone.
- **It is not sandboxed.** Neither the Authorization API nor the bridge SPI is
  available to a sandboxed app, so RDMALink ships outside the App Store as a
  notarized download.
- **It talks to nothing.** There is no network request, no telemetry, no update
  check and no background agent. It is a tool you open, not a thing that lives
  on your Mac.

If RDMALink cannot recognize your Mac, or the Mac has Thunderbolt 4 rather than
5, it puts itself in read-only mode: you can look at everything, and it changes
nothing.

## Requirements

- Apple silicon, macOS 27.
- Thunderbolt 5 ports. Thunderbolt 4 Macs open read-only — RDMA over
  Thunderbolt needs Thunderbolt 5.
- **RDMA over Thunderbolt switched on**, in System Settings › Privacy &
  Security › Developer Tools, followed by a restart. This is not RDMALink's to
  flip: the switch lives in NVRAM and only System Settings sets it. The app
  detects it, deep-links you to the right pane, and notices the moment it is on
  (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) under Decisions, "RDMA
  switch").
- A second Mac at the other end of one Thunderbolt cable, set up the same way.
  Keep it to one cable between any pair: a bridge forwards like a hub, and a
  second cable between the same two Macs makes a loop.

## Install

Download `RDMALink-<version>.dmg` from the
[releases page](https://github.com/dev7a/rdmalink/releases), open it and drag
RDMALink to Applications. The app is signed with a Developer ID and notarized,
so macOS opens it without any override.

Coming: `brew install --cask dev7a/tap/rdmalink`.

### Checking what you downloaded

Every release carries `SHA256SUMS` and `release.json` beside the image. Put the
image next to `SHA256SUMS` and run both of these:

```sh
shasum -a 256 -c SHA256SUMS
spctl --assess --type open --context context:primary-signature -vv RDMALink-<version>.dmg
```

The first must print `OK`. The second must print `source=Notarized Developer ID`
— anything else means the image is not the one Apple notarized. There is more
on this in [script/release/README.md](script/release/README.md).

`release.json` is the build's receipt: the tag, the commit and the tag object
the image was built from, the version and build number, the architecture and
minimum macOS, the team and bundle identifier, Apple's notarization result for
both the app and the image, and the Xcode version that built it.

## Reporting problems

Bugs, port layouts RDMALink does not recognize, and anything it got wrong about
your Mac: [GitHub Issues](https://github.com/dev7a/rdmalink/issues). The app's
Help menu has **Save a Diagnostics File…**, which writes a plain text file with
what RDMALink can see on this Mac and what it changed — that file is the single
most useful thing to attach.

For a security vulnerability, do not open an issue. See
[SECURITY.md](SECURITY.md).

## Build from source

Xcode 27 on macOS 27. The gate is:

```sh
script/test.sh
```

It builds and tests the Core package and the command-line tool, runs the
presentation and stage-math suites and the three release-script tests, and
builds the app Debug with an ad-hoc signature — so it needs no signing identity
and no network.

`script/package_dmg.sh` builds the signed, notarized disk image. It is
maintainer-only: it requires the project's Developer ID Application identity in
your Keychain, and a release is cut by pushing a signed `v<version>` tag, which
builds and notarizes on GitHub. See
[script/release/README.md](script/release/README.md).

There is also `rdmalink`, a read-only command-line companion built by the Core
package: `inventory`, `status`, `refusals`, `changes`, and a preview of what
each operation would do. It never writes anything.

## How it works

- Every string in the app, screen by screen, and the reasoning behind them:
  [docs/UX_SPEC.md](docs/UX_SPEC.md)
- Module layout, the verified macOS constraints behind each decision, packaging
  and the release pipeline: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## License

MIT. See [LICENSE](LICENSE).
