# RDMALink architecture

RDMALink is a non-sandboxed macOS 27 utility that prepares Thunderbolt 5 ports
on the Mac it runs on so they can carry RDMA over Thunderbolt: it removes a
port from the Thunderbolt Bridge, gives it its own network service with IPv4
off and IPv6 link-local only, saves an undo note, and can put everything back.
It changes only the Mac it runs on. There is no peer channel.

The user experience is specified in [UX_SPEC.md](UX_SPEC.md). Every string in
the app comes from there. The 3D stage is prototyped in
[prototype/stage.html](prototype/stage.html); its port catalogue is the
geometry reference for the real model, down to the Mac Studio's back grille,
which `Chassis.grille` carries as a rectangle in face fractions and the stage
draws as one strip on the shell's own outline wearing one alpha-masked tile.
That tile is the only texture in the app, and it is generated at run time,
never loaded: nothing the stage shows comes from an asset. The chassis is the
same silver in both appearances — dark mode changes the light, never the
metal (UX_SPEC §3.4) — and no text is ever drawn on the model: §4.8's legend
and receptacle callout are SwiftUI overlays over the render surface, placed
from `StageMath.project`.

## Decisions (2026-09-19)

| Topic | Decision |
|---|---|
| Distribution | GitHub download, Developer ID + notarized. Never the App Store. |
| Sandbox | Off. Hardened Runtime on. |
| Bridge membership | Edited in-app through the private `SCBridgeInterface*` SPI, probed with `dlsym` at launch, remove-only, verified by reading the kernel back. If any symbol is missing the app falls back to a supervised System Settings hand-off. |
| Privilege | No helper daemon. `AuthorizationCopyRights` for `system.services.systemconfiguration.network`, then `SCPreferencesCreateWithAuthorization`. The credential is non-shared and lasts about 30 s, so every write of one operation happens in a single burst right after the prompt. |
| RDMA switch | Not the app's to flip. Detected from NVRAM `rdma-enable` and `ibv_devices`; the app deep-links to System Settings › Privacy & Security › Developer Tools (`x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_DevTools`) and re-checks after the restart. |
| Scope per run | Local Mac only. The user runs the app on each Mac and picks the ports. |
| 3D | Go. Real proportions and port positions, generic surfaces, no logo. Renderer decision (RealityKit vs three.js in a WebView) is open until ML1. |
| Milestones | `ML0` foundations and spikes · `ML1` read-only inspector with the stage · `ML2` configure and undo · `ML3` polish, change log, settings — and the command-line tool loses its mutating half: since ML3 the app is the only thing that writes, and `rdmalink` reads only. The hardware proofs recorded below for 2026-09-20 were run with its former write commands. Never write `M0`. |

## Verified constraints (macOS 27.2, Mac Studio M3 Ultra, 2026-09-19)

- `SCBridgeInterface*` is in no public header. Eleven symbols resolve under
  their plain names; `SCBridgeInterfaceCopyActive` and
  `SCBridgeInterfaceUpdateConfiguration` resolve only as
  `_SCBridgeInterfaceCopyActive` / `_SCBridgeInterfaceUpdateConfiguration`.
  There is no `kSCNetworkInterfaceTypeBridge` constant in the SDK either.
  `networksetup` and `scutil` have no bridge verbs.
- The authorization right `system.services.systemconfiguration.network`
  resolves through `authenticate-admin-nonshared` (shared=false, timeout 30 s).
  `system.preferences.network` is the Network pane's own right and does not
  satisfy configd.
- Everything the old script did (per-port `SCNetworkServiceCreate`, IPv4 off,
  IPv6 `kSCValNetIPv6ConfigMethodLinkLocal`, commit, apply, restore) is public
  API. Only bridge membership is not.
- Public IOKit keys that are load-bearing: `AppleThunderboltIPPort` →
  `IOLocation` (receptacle index) and `IOLinkStatus`; its `IOEthernetInterface`
  child → `BSD Name`. Never derive `enN` from the receptacle index.
  `IOLinkStatus` is 3 for a linked Mac and 1 for empty *and* for a dock;
  `IOLinkSpeed` is a constant and useless.
- Physical position is derivable at runtime on the Mac Studio through
  undocumented IODeviceTree keys: `hpm0..5` (`AppleARMSPMIDevice`) carry
  `port-location` (`back-left`, `front-right`, …) and an `acio-parent` phandle
  that resolves to the `acioN` node holding the `AppleThunderboltIPPort`.
  Treat as best-effort enrichment behind a public-key fallback; unverified on
  other models.
- **What macOS calls this Mac** (verified on Mac15,14 2026-09-20): the device
  tree's `product` node, `IORegistryEntryFromPath(kIOMainPortDefault,
  "IODeviceTree:/product")`, carries `product-name` and `product-description`
  (`Mac Studio (2025)`), `product-soc-name` (`Apple M3 Ultra`),
  `builtin-battery` (0) and `fdr-product-type` (`Mac15,14`, the same as
  `hw.model` and `hw.product`), each a NUL-terminated C string in `Data`.
  Recognition (UX_SPEC §4.7) is the identifier catalogue first; a Mac it does
  not list is recognized when the family parsed from `product-name` (the
  text before the parenthesis) and the `port-location` layout it reports
  match one archetype's Thunderbolt table exactly, and stays unknown
  otherwise. The layout is one position per Thunderbolt-IP receptacle
  macOS lists, not per position the probe placed: a receptacle the probe
  could not join to a `port-location` node counts as a hole and refuses,
  so a partial probe can never shrink a six-port Studio into the four-port
  table. Undocumented, so enrichment under rule 5: absent, the Mac is
  called `Mac` and drawn as the stand-in. The MacBook Pro's `port-location`
  spellings are not yet recorded; `PortPosition.parse` accepts `left-rear`,
  `left-front` and `right`.
- The only public live event is `SCDynamicStore`
  `State:/Network/Interface/<bsd>/Link` (and `/IPv6`), which fires on
  Thunderbolt-IP link transitions only. Dock plug/unplug may not fire
  anything; a one-second state diff runs underneath.
- **Thunderbolt domain identity** (measured 2026-09-20, `IOThunderboltFamily`
  9.3.3, unprivileged `ioreg`): the private key `Domain UUID` is published in
  two places. `IOThunderboltLocalNode`, the parent of the
  `AppleThunderboltIPService` above each `AppleThunderboltIPPort`, carries the
  receptacle's own domain — one per controller, and on Apple Silicon one
  controller per receptacle (six local nodes on Mac15,14, one under each
  `acioN`), so it is per port, not per Mac. `IOThunderboltXDomainLink`, under
  the local switch on the same controller, carries the far end's domain plus
  `Device Name` (`Mac17,7`). The values are symmetric across two Macs: the
  MacBook's local nodes report exactly what this Mac's XDomain links say, and
  vice versa. Docks put an `IOThunderboltSwitch*` under the local switch and
  no XDomain link; empty receptacles have neither. So R2 is "the peer domain
  on port P is the own domain of another port Q of this Mac", mutual and
  unique, and it never fires on anything but that equality. Private keys, so
  enrichment under rule 5: absent → `domainUUID` nil, `peerDomainUUIDs`
  empty, `loopedBackTo` nil, R2 silent. Not in any SDK header. Compared at
  one instant only, never persisted. A real self-link was **not** observed:
  no loopback cable on the rig, so whether macOS brings up an XDomain link
  between two of its own controllers is untested.
- Kernel bridge membership is visible in `ifconfig` output (`member:` lines
  under `bridgeN`; `ifconfig -a` and `ifconfig bridge0` both print them). A
  port must be out of every bridge, even an inactive one. The kernel list can
  change without RDMALink writing anything: when the first real write failed
  on 2026-09-20 the app's own read showed `bridge0` with no members at all,
  and twenty minutes later `ifconfig` listed `en5` in it again — no membership
  write had been committed in between.
- Two Thunderbolt cables between the same pair of Macs loop only when a
  bridge forwards between them, so R1 counts a linked Mac only through a
  bridge: it fires when two ports with a Mac on the end share a bridge. Two
  cables on two standalone ports are two point-to-point links — the finished
  state — and pass.
- **`RealityViewCameraContent.project(point:to:)` does not give the stage's
  screen positions** (measured 2026-09-20, macOS 27.2): with the stage's own
  `PerspectiveCamera` active and a 580 × 668 pt view, the camera's target
  projected 13 pt off the viewport's centre and 5 cm at 0.5 m came back as
  14.5 pt where the rig's 37.85° field of view puts it at 97 pt. So the two
  §4.8 overlays — the legend that yields to the chassis and the callout
  beside a receptacle — are laid out from `StageMath.project`, the rig's own
  look-at and perspective over the pose the scene is holding, which is also
  the pose the review capture renders with. Hit testing keeps
  `entities(at:in:)`, which was not affected. Two consequences of laying
  out from the projection: the callout is shown only while its receptacle's
  face is the one in front (every other face's centres project too, onto
  the far side of the chassis), and it stands off the top of the whole row
  on that face, because a row seen three-quarters on rises across the
  screen and the neighbours' rings sit above the hovered centre. The legend
  moves to the top-trailing corner only when that corner is clear; the
  chassis's projected bounds span nearly the stage's width, so a box that
  reaches one top corner can reach both, and then the legend stays.
- **Bridge membership is two facts, not one** (measured 2026-09-20). The
  network preferences keep their own member list —
  `VirtualNetworkInterfaces` → `Bridge` → `bridgeN` → `Interfaces`, with
  `UserDefinedName` beside it — and it can disagree with the kernel:
  `bridge0` stored with `en5` in it while the kernel `bridge0` had no members
  at all. While the stored list claims a port, `SCNetworkServiceCreate`
  refuses on it with `kSCStatusFailed` (1001), whose `SCErrorString` is the
  single word `Failed!`. So a port is "in a bridge" when **either** read says
  so, both are read without privilege (`SCPreferencesCreate` plus
  `SCBridgeInterfaceCopyAll`, falling back to the world-readable
  `/Library/Preferences/SystemConfiguration/preferences.plist`), and every
  membership change is verified against both.
- `_SCBridgeInterfaceUpdateConfiguration` is root-only in practice: from the
  authorized but non-root CLI it fails with `bridge0: could not set MAC
  address: Operation not permitted` (2026-09-20). configd runs the same call
  itself a few milliseconds after every `SCPreferencesApplyChanges` that
  changes the bridge configuration (`InterfaceNamer`). An apply that changes
  nothing makes it attempt nothing (measured 05:06:49): applying again is
  not a retry.
- **The kernel refuses a member that still has IP attached.** Measured three
  times on 2026-09-20 as `could not add interface "en5" to bridge "bridge0":
  Operation not supported on socket`: System Settings' own add at 03:57:59
  (which is how the stored/kernel disagreement that broke the first write
  came about), RDMALink's restore at 04:45:55, and again at 05:06:45 — where
  the log shows the order: apply, configd's add attempt 8 ms later and
  refused, IPConfiguration's `SIOCPROTODETACH_IN6` on the port 40 ms after
  that. With the port quiet (down, no service, no addresses) the add was
  taken on the first apply at 05:03:37, 9 ms after it. So a service is
  deleted in a commit of its own, the port is given until the window closes
  to go quiet (`KernelVerification.waitUntilQuiet`), and only then is the
  membership written and committed (`BridgeRejoin`). When the kernel still
  has not followed, the retry is to take the membership out and put it back
  in commits of their own; R20 keeps the note if that fails too. Proven at
  11:36:42: a stored list that already had `en5` (left by a refused
  restore) was rewritten in two commits 275 ms apart, and configd added the
  member 14 ms after the second apply. At 11:38:01 a restore with the
  service present went through first time: deletion applied, IPv6 detached
  47 ms later, the port quiet within 470 ms, membership applied, member
  added 35 ms after that. Return to Bridge on a port removed by hand in
  System Settings passed at 11:40:23 the same way (note written, no service
  to delete, member added 9 ms after the apply).

## Layout

```
RDMALink.xcodeproj        the app (App/) linking the local package
App/                      SwiftUI app: window, stage, assistant column
Packages/RDMALinkCore/    everything shared with the CLI and tests
  Sources/RDMALinkCore/
    Inventory/            hardware model, ports, positions, live watcher
    Network/              ifconfig/SC reads, authorization, setup, bridge SPI
    Status/               RDMA switch and devices
    Store/                baseline (undo note), change log, and the moment
                          format the copy quotes (`Moment`: the locale's
                          short time, never a 12-hour hour without AM/PM)
    Refusals/             the hard rules as pure functions
  Sources/rdmalink/       command-line companion: read-only diagnostics
  Tests/RDMALinkCoreTests Swift Testing
docs/                     spec, this file, prototype
script/                   test.sh, build and packaging
```

## Packaging

`script/package_dmg.sh` builds what a GitHub release ships. Release signs
with the Developer ID Application identity of team BV5XC39R5P (manual
signing, hardened runtime, secure timestamp); Debug stays ad-hoc so
`script/test.sh` and daily builds need no identity. The script requires
exactly one such identity in the Keychain and passes its SHA-1 to the
archive, the export and the image's `codesign`, so no same-named identity
can be picked up. It archives Release for arm64 only (macOS 27 runs on
Apple silicon only), exports with `method: developer-id`, and verifies the
exported app before it ships: `codesign --verify --strict --deep`, Developer
ID authority and team, hardened-runtime flag (`0x10000` in the CodeDirectory
flags), secure timestamp, empty signed entitlements (the bridge SPI is reached
with `dlsym` and the Authorization API needs none), and every Mach-O file
arm64 only. The app goes into a UDZO image (volume `RDMALink`, with an
Applications link), checked with `hdiutil verify`, signed with the same
identity, and mounted once to confirm the code hash on the image is the
exported one. Without `--notarize` the script stops there, writes
`dist/RDMALink-<version>-unnotarized.dmg` and prints the notarize command;
with it, the script first checks that the `rotorfs` notarytool Keychain
profile exists, then submits the app (zipped) through it and staples it
before it goes into the image, submits and staples the image too, assesses
both with `spctl` (`source=Notarized Developer ID` required) and writes
`dist/RDMALink-<version>.dmg`, the file a release ships.

## Core contracts

These types are the seams between modules. Keep them small and value-typed.

```swift
public enum Archetype: Sendable { case studioFour, studioSix, mini, notebook, unknown }
public enum Recognition: Sendable { case identifier, familyAndLayout, none }

public struct HardwareModel: Sendable {
    public var identifier: String        // hw.model, e.g. "Mac15,14"
    public var marketingName: String     // "Mac Studio": the catalogue's name, else the
                                         // device tree's product family, else "Mac"
    public var chip: String              // "M3 Ultra"
    public var archetype: Archetype
    public var recognition: Recognition  // which UX_SPEC §4.7 rule decided the archetype
}

public enum PortFace: String, Sendable { case back, front, left, right }
public enum LinkState: Sendable { case empty, device, macLinkComingUp, macLinked }

public struct ThunderboltPort: Sendable, Identifiable {
    public var id: String                // stable: the IORegistry entry id or BSD name
    public var receptacle: Int           // IOLocation, 1-based
    public var bsdName: String           // "en6"
    public var face: PortFace?           // from port-location when known
    public var positionName: String      // "Back, far left" or "Thunderbolt port 3"
    public var isThunderbolt: Bool       // false for USB-only receptacles
    public var link: LinkState
    public var bridges: [BridgeMembership]  // kernel ∪ stored, each with its source
    public var linkLocal: [String]       // fe80:: addresses without the %scope
    public var domainUUID: String?       // own Thunderbolt domain, nil when not published
    public var peerDomainUUIDs: [String] // far-end domains on this controller
    public var loopedBackTo: String?     // the other receptacle on the same cable (R2)
}

public struct Inventory: Sendable {
    public var model: HardwareModel
    public var ports: [ThunderboltPort]  // physical order
    public var rdma: RDMAStatus
}

public enum RDMAStatus: Sendable { case unknown, off, onAfterRestart, on(devices: [String]) }
```

Mutations go through one type per operation, each with `preview()` (what would
change, no writes), `perform(session:)` (all writes in one authorized burst,
baseline written first) and read-back verification. No mutation exists without
its inverse.

## Rules the code must keep

1. The baseline is written before the first write. If it cannot be written,
   nothing is changed.
2. Services are matched by identifier, never by name.
3. The app never creates or deletes a bridge. It only removes a member, and
   only puts a member back.
4. Every refusal in the spec is a pure function over observed state, with a
   test. There is no override.
5. Public IOKit and SystemConfiguration keys are load-bearing; undocumented
   keys and the bridge SPI degrade cleanly when absent.
6. Swift 6 language mode, strict concurrency, warnings are errors.
