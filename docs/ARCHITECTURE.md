# RDMALink architecture

RDMALink is a non-sandboxed macOS 27 utility that prepares Thunderbolt 5 ports
on the Mac it runs on so they can carry RDMA over Thunderbolt: it removes a
port from the Thunderbolt Bridge, gives it its own network service with IPv4
off and IPv6 link-local only, saves an undo note, and can put everything back.
It changes only the Mac it runs on. There is no peer channel.

The user experience is specified in [UX_SPEC.md](UX_SPEC.md). Every string in
the app comes from there. The 3D stage is prototyped in
[prototype/stage.html](prototype/stage.html); its port catalogue is the
geometry reference for the real model.

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
| Milestones | `ML0` foundations and spikes · `ML1` read-only inspector with the stage · `ML2` configure and undo · `ML3` polish, change log, settings. Never write `M0`. |

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
- The only public live event is `SCDynamicStore`
  `State:/Network/Interface/<bsd>/Link` (and `/IPv6`), which fires on
  Thunderbolt-IP link transitions only. Dock plug/unplug may not fire
  anything; a one-second state diff runs underneath.
- Kernel bridge membership is visible only in `ifconfig -a` output
  (`member:` lines under `bridgeN`). A port must be out of every bridge, even
  an inactive one. Two Thunderbolt cables between the same pair of bridged
  Macs can create an Ethernet forwarding loop.

## Layout

```
RDMALink.xcodeproj        the app (App/) linking the local package
App/                      SwiftUI app: window, stage, assistant column
Packages/RDMALinkCore/    everything shared with the CLI and tests
  Sources/RDMALinkCore/
    Inventory/            hardware model, ports, positions, live watcher
    Network/              ifconfig/SC reads, authorization, setup, bridge SPI
    Status/               RDMA switch and devices
    Store/                baseline (undo note) and change log
    Refusals/             the hard rules as pure functions
  Sources/rdmalink/       command-line companion: diagnostics and spikes
  Tests/RDMALinkCoreTests Swift Testing
docs/                     spec, this file, prototype
script/                   test.sh, build and packaging
```

## Core contracts

These types are the seams between modules. Keep them small and value-typed.

```swift
public enum Archetype: Sendable { case studioFour, studioSix, mini, notebook, unknown }

public struct HardwareModel: Sendable {
    public var identifier: String        // hw.model, e.g. "Mac15,14"
    public var marketingName: String     // "Mac Studio"
    public var chip: String              // "M3 Ultra"
    public var archetype: Archetype
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
    public var bridges: [String]         // kernel bridges this port is a member of
    public var linkLocal: [String]       // fe80:: addresses without the %scope
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
