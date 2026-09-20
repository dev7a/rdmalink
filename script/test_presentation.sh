#!/usr/bin/env bash
# Exercises the hub's pure presentation on its own: UX_SPEC §S1's ready row,
# the port rows, and what an undo note makes of a port (App/Model/PortSnapshot,
# App/Presentation/PortPresentation, App/Presentation/ThisMacPresentation).
#
# The app target has no test bundle, and these four files import nothing but
# Foundation and RDMALinkCore, so — like script/test_stage_math.sh — they are
# compiled against the Core module `swift build` left behind and run as a
# plain executable. Every sentence asserted here is §S1's own.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_BIN="$(cd "$ROOT_DIR/Packages/RDMALinkCore" && swift build --show-bin-path)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/main.swift" <<'SWIFT'
import Foundation
import RDMALinkCore

var failures = 0

@MainActor func check(_ condition: Bool, _ what: String) {
    if condition { return }
    failures += 1
    FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
}

func text(_ resource: LocalizedStringResource) -> String { String(localized: resource) }

func port(
    _ bsdName: String, _ positionName: String, link: LinkState = .empty,
    bridges: [ThunderboltPort.BridgeMembership] = [], isThunderbolt: Bool = true
) -> ThunderboltPort {
    ThunderboltPort(
        id: bsdName.isEmpty ? positionName : bsdName, receptacle: 1, bsdName: bsdName,
        face: .back, positionName: positionName, isThunderbolt: isThunderbolt, link: link,
        bridges: bridges)
}

let bridge0 = ThunderboltPort.BridgeMembership(
    name: "bridge0", displayName: "Thunderbolt Bridge", isUp: true, source: .both)
let returnRecord = PortBaseline(
    bsdName: "en5", receptacle: 4, positionName: "Back, far left",
    returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
let ownNote = PortBaseline(
    bsdName: "en6", receptacle: 1, positionName: "Back, left middle",
    bridges: [BridgeMembership(bridgeName: "bridge0", members: ["en5", "en6"], isActive: true)],
    createdService: CreatedServiceRecord(identifier: "MINE", interfaceBSDName: "en6"))
let adoptedNote = PortBaseline.adopted(bsdName: "en7", receptacle: 2, positionName: "Back, right middle")

func snapshot(
    _ port: ThunderboltPort, configuration: PortConfiguration?, baseline: PortBaseline? = nil
) -> PortSnapshot {
    PortSnapshot(port: port, bridges: port.bridges, configuration: configuration, baseline: baseline)
}

// MARK: §S1's ready row, all five sentences, singulars included.

check(text(ThisMacPresentation.readyText(ready: [], setUpOutside: 0))
      == "Ports ready for RDMA — None yet", "ready row: none yet")
check(text(ThisMacPresentation.readyText(ready: ["Back, far left"], setUpOutside: 0))
      == "Ports ready for RDMA — Back, far left", "ready row: one name")
check(text(ThisMacPresentation.readyText(ready: ["Back, far left", "Back, far right"], setUpOutside: 0))
      == "Ports ready for RDMA — Back, far left and Back, far right", "ready row: two names")
check(text(ThisMacPresentation.readyText(ready: [], setUpOutside: 5))
      == "Ports ready for RDMA — None by RDMALink · five set up outside it", "ready row: five outside")
check(text(ThisMacPresentation.readyText(ready: [], setUpOutside: 1))
      == "Ports ready for RDMA — None by RDMALink · one set up outside it", "ready row: one outside")
check(text(ThisMacPresentation.readyText(ready: ["Back, far left"], setUpOutside: 2))
      == "Ports ready for RDMA — Back, far left · two more set up outside RDMALink", "ready row: two more")
check(text(ThisMacPresentation.readyText(ready: ["Back, far left"], setUpOutside: 1))
      == "Ports ready for RDMA — Back, far left · one more set up outside RDMALink", "ready row: one more")
check(ThisMacPresentation.spelledOut(4) == "Four", "counts are spelled out, capitalised")
check(ThisMacPresentation.spelledOut(6, capitalized: false) == "six", "and lowercase")
// The sentences are English whatever the user's locale is (run with
// -AppleLocale fr_FR below): never "cinq", never "et".
check(ThisMacPresentation.spelledOut(5, capitalized: false) == "five", "spelled out in English")
check(!text(ThisMacPresentation.readyText(ready: ["A", "B"], setUpOutside: 0)).contains(" et "),
      "the list is joined in English")

// MARK: The row over real snapshots: what counts as ready and as outside.

let managed = snapshot(port("en6", "Back, left middle"), configuration: .readyForRDMA(serviceID: "MINE"),
                       baseline: ownNote)
let adopted = snapshot(port("en7", "Back, right middle"), configuration: .readyForRDMA(serviceID: "THEIRS"),
                       baseline: adoptedNote)
let outside = snapshot(port("en2", "Back, far right"), configuration: .readyForRDMA(serviceID: "OTHER"))
let returned = snapshot(port("en5", "Back, far left", bridges: [bridge0]),
                        configuration: .unconfigured(bridges: ["bridge0"]), baseline: returnRecord)
let plain = snapshot(port("en3", "Front, left", bridges: [bridge0]),
                     configuration: .unconfigured(bridges: ["bridge0"]))
check(managed.readiness == .managed, "own note and a match is managed")
check(adopted.readiness == .adopted, "adopted note and a match is adopted")
check(outside.readiness == .setUpElsewhere, "a match with no note is set up elsewhere")
check(returned.readiness == .returned, "a return record that holds is returned")
check(plain.readiness == .plain, "a bridge member with no note is plain")
let all = [managed, adopted, outside, returned, plain]
check(text(ThisMacPresentation.readyRow(all).text)
      == "Ports ready for RDMA — Back, left middle and Back, right middle · one more set up outside RDMALink",
      "the row counts RDMALink's and adopted ports as ready, and the rest as outside")
check(all.ready.map(\.port.bsdName) == ["en6", "en7"], "ready is managed and adopted only")
check(all.adoptable.map(\.port.bsdName) == ["en2"], "adoptable is set up elsewhere only")

// MARK: §4.3 / §S1: the returned row.

let returnedRow = PortRowPresentation(snapshot: returned)
check(text(returnedRow.detail.state) == "Back in the bridge", "returned row state")
check(returnedRow.detail.link.map(text) == "Nothing plugged in", "returned row keeps the link subtitle")
check(returnedRow.detail.membership.map(text) == "In the Thunderbolt Bridge",
      "returned row keeps the membership phrase")
check(returnedRow.detail.address == nil, "returned row has no address")
check(returnedRow.symbol == "arrow.uturn.backward.circle" && returnedRow.symbolStyle == .secondary,
      "returned row symbol")
check(returnedRow.actions == [.setItUpAgain(portID: "en5")], "returned row offers Set It Up Again only")
check(returnedRow.compactBadge == nil, "returned row has no Ready badge")
check(returnedRow.accessibilityLabel
      == "Back, far left. Thunderbolt port. Back in the bridge. Nothing plugged in. In the Thunderbolt Bridge.",
      "returned row accessibility label carries link and membership")
let returnedLinked = snapshot(port("en5", "Back, far left", link: .macLinked, bridges: [bridge0]),
                              configuration: .unconfigured(bridges: ["bridge0"]), baseline: returnRecord)
check(PortRowPresentation(snapshot: returnedLinked).detail.link.map(text) == "Linked to another Mac",
      "returned row follows the link state")

// MARK: A return record whose port has moved on describes nothing current.

// Out of the bridge and given a matching service by hand: §S1's "Set up
// outside RDMALink", adoptable, and counted as outside — never plain.
let staleMatch = snapshot(port("en5", "Back, far left"), configuration: .readyForRDMA(serviceID: "HAND"),
                          baseline: returnRecord)
check(staleMatch.readiness == .setUpElsewhere, "stale return record over a full match reads set up elsewhere")
check(staleMatch.readiness.isAdoptable, "and is adoptable")
check(PortRowPresentation(snapshot: staleMatch).actions
      == [.adopt(portID: "en5"), .returnToBridge(portID: "en5")], "and the row offers Adopt…")
check(text(PortRowPresentation(snapshot: staleMatch).detail.state) == "Set up outside RDMALink",
      "and reads Set up outside RDMALink")
check(text(ThisMacPresentation.readyRow([staleMatch, outside]).text)
      == "Ports ready for RDMA — None by RDMALink · two set up outside it", "and the ready row counts it")
// Out of the bridge and left bare: plain, and it can be put back from the row.
let staleBare = snapshot(port("en5", "Back, far left"), configuration: .unconfigured(bridges: []),
                         baseline: returnRecord)
check(staleBare.readiness == .plain, "stale return record over a bare port reads plain")
check(PortRowPresentation(snapshot: staleBare).actions == [.returnToBridge(portID: "en5")],
      "a bare port out of every bridge carries Return to Bridge…")
check(text(PortRowPresentation(snapshot: staleBare).detail.state) == "Nothing plugged in"
      && PortRowPresentation(snapshot: staleBare).detail.membership.map(text) == "Not in any bridge",
      "and reads the plain subtitle")
// Out of the bridge with a near match: plain with Adopt… — and never drift.
let staleNear = snapshot(
    port("en5", "Back, far left"),
    configuration: .nearMatch(serviceID: "HAND", differences: [.ipv4NotOff(method: "DHCP")]), baseline: returnRecord)
check(staleNear.readiness == .plain, "a return record is never drift")
check(PortRowPresentation(snapshot: staleNear).actions
      == [.adopt(portID: "en5"), .returnToBridge(portID: "en5")], "a near match offers Adopt… and the return")

// MARK: §7.5: any port out of every bridge can be put back, bare or not.

check(snapshot(port("en2", "Back, far right"), configuration: .unconfigured(bridges: [])).isOutOfEveryBridge,
      "a bare port out of every bridge")
check(PortRowPresentation(snapshot: snapshot(port("en2", "Back, far right"),
                                             configuration: .unconfigured(bridges: []))).actions
      == [.returnToBridge(portID: "en2")], "carries Return to Bridge…")
check(!plain.isOutOfEveryBridge && PortRowPresentation(snapshot: plain).actions.isEmpty,
      "a bridge member carries nothing")
check(!snapshot(port("en2", "Back, far right"), configuration: nil).isOutOfEveryBridge,
      "a configuration that could not be read is not out of every bridge")
check(PortRowPresentation(snapshot: snapshot(port("", "Front, right", isThunderbolt: false),
                                             configuration: nil)).actions.isEmpty,
      "a USB-only receptacle carries nothing")
check(outside.isOutOfEveryBridge
      && PortRowPresentation(snapshot: outside).actions == [.adopt(portID: "en2"), .returnToBridge(portID: "en2")],
      "set up elsewhere offers Adopt… and Return to Bridge…")
check(PortRowPresentation(snapshot: managed).actions == [.restore(portID: "en6")], "RDMALink's own port offers Restore… alone")
check(PortRowPresentation(snapshot: adopted).actions == [.returnToBridge(portID: "en7"), .stopManaging(portID: "en7")],
      "an adopted port offers the return and Stop Managing…")

// MARK: Drift is only ever about a setup RDMALink made or adopted.

let drifted = snapshot(port("en6", "Back, left middle", bridges: [bridge0]),
                       configuration: .unconfigured(bridges: ["bridge0"]), baseline: ownNote)
check(drifted.readiness == .drifted, "own note and no service is drift")
check(text(PortRowPresentation(snapshot: drifted).detail.state) == "Not set up any more", "drift row state")
check(PortRowPresentation(snapshot: drifted).actions == [.setItUpAgain(portID: "en6")], "drift row action")
check(snapshot(port("en5", "Back, far left"), configuration: .unconfigured(bridges: []), baseline: returnRecord)
      .readiness != .drifted, "a return record never drifts")

if failures > 0 {
    FileHandle.standardError.write(Data("test_presentation: \(failures) failed\n".utf8))
    exit(1)
}
print("test_presentation: all passed")
SWIFT

xcrun swiftc -swift-version 6 -warnings-as-errors \
  -I "$CORE_BIN" -L "$CORE_BIN" -lRDMALinkCore \
  -framework SystemConfiguration -framework IOKit -framework Security \
  -o "$WORK_DIR/test_presentation" \
  "$ROOT_DIR/App/Model/PortSnapshot.swift" \
  "$ROOT_DIR/App/Model/HubActions.swift" \
  "$ROOT_DIR/App/Presentation/PortPresentation.swift" \
  "$ROOT_DIR/App/Presentation/ThisMacPresentation.swift" \
  "$WORK_DIR/main.swift"

"$WORK_DIR/test_presentation"
# The same assertions under a French locale: §S1's sentences stay English.
"$WORK_DIR/test_presentation" -AppleLocale fr_FR -AppleLanguages "(fr)" >/dev/null
