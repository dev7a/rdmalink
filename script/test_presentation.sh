#!/usr/bin/env bash
# Exercises the hub's pure presentation on its own: UX_SPEC §S1's ready row,
# the port rows, and what an undo note makes of a port (App/Model/PortSnapshot,
# App/Presentation/PortPresentation, App/Presentation/ThisMacPresentation) —
# §S3's first row, where R2 has to win over R1 (App/Flows/PreflightReport,
# with the two files its button row and refusal card reach into), and §S8's
# subject (App/Presentation/OtherMacPresentation) — and the Restore sheet's
# button rows (App/Presentation/RestorePresentation), the only place §6.2's
# rows for R19, R20, R21, R28 and R30 are written down — and §4.8's two aids:
# the legend's rows from the stage's own ring decision (App/Stage/StageLegend,
# with App/Stage/StageModel and StageMath under it) and the callout's words
# from the row's presentation.
#
# The app target has no test bundle, and these files import nothing but
# Foundation, Observation, AppKit and RDMALinkCore, so — like script/test_stage_math.sh —
# they are compiled against the Core module `swift build` left behind and run
# as a plain executable. Every sentence asserted here is §S1's or §S3's own.
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

// MARK: §S3 row 1 — R2 is named ahead of R1, and rings the two ends of the cable.

let farLeft = PreflightPort(id: "en5", positionName: "Back, far left")
let farRight = PreflightPort(id: "en6", positionName: "Back, far right")
var findings = PreflightFindings()
findings.mountedThunderboltVolumes = []
findings.route = .wiFi
findings.notesWritability = .writable(availableBytes: nil)
findings.portsLoopedBack = [farLeft, farRight]
let looped = PreflightReport(findings)
check(looped.rows[0].state == .unsatisfied, "R2 row is unsatisfied")
check(looped.rows[0].finding.map(text)
      == "Both ends of one cable are in this Mac, on Back, far left and Back, far right. Unplug one end and put it in the other Mac.",
      "R2 row finding is §S3's")
check(looped.continueReason.map(text) == "Unplug one end of that cable to continue.", "R2 disabled-Continue reason")
check(!looped.canContinue, "R2 blocks Continue")
check(looped.attentionPortIDs == ["en5", "en6"], "R2 rings both ends of the cable")

// The same cable with both ends reading as linked Macs in one bridge — every
// input R1 has — is still R2, and rings R2's pair.
findings.portsWithAMac = [farLeft, farRight]
findings.portsInALoop = [farLeft, farRight]
let both = PreflightReport(findings)
check(both.rows[0].finding.map(text)?.hasPrefix("Both ends of one cable are in this Mac") == true,
      "R2 wins over R1")
check(both.continueReason.map(text) == "Unplug one end of that cable to continue.", "R2 reason wins over R1's")

// Without the loop, the same two linked, bridged ports are R1.
findings.portsLoopedBack = []
let r1 = PreflightReport(findings)
check(r1.rows[0].finding.map(text)
      == "Two Macs are connected, on Back, far left and Back, far right. Unplug one and I'll pick this back up.",
      "R1 row finding is §S3's")
check(r1.continueReason.map(text) == "Unplug one of the two cables to continue.", "R1 disabled-Continue reason")
check(r1.attentionPortIDs == ["en5", "en6"], "R1 rings the ports in the loop")

// The hub's snapshots carry Core's pairing through to the findings.
let cable = [
    snapshot(port("en5", "Back, far left", link: .macLinked, bridges: [bridge0]), configuration: nil),
    snapshot(port("en6", "Back, far right", link: .macLinked, bridges: [bridge0]), configuration: nil),
].map { snap -> PortSnapshot in
    var snap = snap
    snap.port.loopedBackTo = snap.port.bsdName == "en5" ? "en6" : "en5"
    return snap
}
check(PreflightFindings(ports: cable).portsLoopedBack == [farLeft, farRight],
      "port snapshots feed R2's pair")
check(PreflightFindings(ports: cable).isLoopedBackIntoThisMac, "port snapshots say looped back")
check(PreflightFindings(ports: [cable[0]]).portsLoopedBack.isEmpty, "one end alone is not a loop")

// R2's refusal card: self-clearing, no button, R1's symbol.
let r2 = WizardRefusal(Refusals.loopedBackIntoThisMac(cable.map(\.observed))!)
check(r2.code == "R2" && r2.actions.isEmpty && r2.symbol == "cable.connector", "R2 card has no button")
check(r2.watchingLine.map(text) == "I'll keep watching — when this is sorted I'll carry straight on.",
      "R2 card keeps watching")
check(text(r2.headline) == "Both ends of that cable are in this Mac", "R2 card headline is §6.2's")

// MARK: §S8 — which port "this link" is, and when the far end has answered.

let linkedManaged = snapshot(
    port("en6", "Back, left middle", link: .macLinked), configuration: .readyForRDMA(serviceID: "MINE"),
    baseline: ownNote)
var addressed = linkedManaged
addressed.port.linkLocal = ["fe80::1c3d:5aff:fe22:9b04"]
check(OtherMacReport(ports: [plain, outside]).subjectID == nil, "a Mac with no ready port has no subject")
check(OtherMacReport(ports: [plain, outside]).address == nil
      && !OtherMacReport(ports: [plain, outside]).answered, "and no address, and nothing has answered")
check(OtherMacReport(ports: [outside, managed]).subjectID == "en6",
      "a port set up outside RDMALink is never the subject; RDMALink's own is")
check(OtherMacReport(ports: [managed, addressed]).subjectID == "en6"
      && OtherMacReport(ports: [managed, addressed]).address == "fe80::1c3d:5aff:fe22:9b04%en6",
      "the first ready port with an address is the subject, and step 4 names it whole")
check(OtherMacReport(ports: [managed]).address == nil, "a ready port with no address yet has none to name")
check(OtherMacReport(ports: [adopted]).subjectID == "en7", "an adopted port is RDMALink's to hand out")
check(!OtherMacReport(ports: [managed]).answered, "nothing plugged in has not answered")
check(OtherMacReport(ports: [linkedManaged]).answered, "a Mac at the far end has answered")
check(!OtherMacReport(ports: [snapshot(port("en6", "Back, left middle", link: .macLinkComingUp),
                                       configuration: .readyForRDMA(serviceID: "MINE"), baseline: ownNote)]).answered,
      "a link still coming up has not answered yet")

// MARK: §6.2's button rows in the Restore sheet, reversed: the spec writes the
// default first, and the sheet makes the last element the default.

func titles(_ code: RefusalCode) -> [String] {
    RestoreRefusals.actions(for: code).map { text($0.title) }
}
check(titles(.undoNoteMissing) == ["Stop Managing This Port", "Copy These Steps", "Open Network Settings"],
      "R19: Open Network Settings (default) · Copy These Steps · Stop Managing This Port")
check(titles(.notBackInBridge) == ["Copy These Steps", "Open Network Settings", "Try Again"],
      "R20: Try Again (default) · Open Network Settings · Copy These Steps")
check(titles(.originalBridgeGone) == ["Leave Everything Alone", "Remove My Service Only"],
      "R21: Remove My Service Only (default) · Leave Everything Alone")
check(titles(.createdServiceEdited) == ["Leave Everything Alone", "Open Network Settings", "Stop Managing…"],
      "R28: Stop Managing… · Open Network Settings · Leave Everything Alone, and no Copy Details")
check(titles(.noteIsAReturnRecord) == ["Cancel", "Stop Managing…", "Set It Up Again"],
      "R30: Set It Up Again (default) · Stop Managing… · Cancel")
check(!RestoreRefusals.actions(for: .createdServiceEdited).contains(.copyDetails)
      && !RestoreRefusals.actions(for: .noteIsAReturnRecord).contains(.copyDetails),
      "a refusal raised before anything is written carries no Copy Details")

// MARK: §4.8 — the legend's rows, from the same ring decision the stage makes.

func cfg(_ snapshot: PortSnapshot) -> StagePort.Configuration { StagePort.Configuration(snapshot) }
check(cfg(managed) == .ready && cfg(adopted) == .ready, "RDMALink's own and adopted ports wear the solid accent ring")
check(cfg(outside) == .outside, "set up elsewhere wears the double hairline")
check(cfg(returned) == .bridge && cfg(plain) == .bridge, "a bridge member wears the segmented ring, returned or not")
check(cfg(drifted) == .drift, "drift wears the dashed ring")
check(cfg(staleBare) == StagePort.Configuration.none, "out of every bridge with nothing on it wears no ring")
let legendLabels = StageLegend.rows(for: [managed, adopted, outside, returned, plain, drifted, staleBare].map(cfg))
    .map { text($0.label) }
check(legendLabels == ["In a bridge", "Standalone", "Set up outside RDMALink", "Ready for RDMA", "Needs a look"],
      "the legend lists every shape present, in §4.8's order, once each")
check(StageLegend.rows(for: [plain, outside, outside].map(cfg)).map { text($0.label) }
      == ["In a bridge", "Set up outside RDMALink"],
      "this rig's legend: one bridged port and five set up outside read as two lines")
check(StageLegend.rows(for: [StagePort.Configuration]()).isEmpty, "no ports, no legend")
let usbStage = StagePort(
    id: "usb", face: .front, physicalIndex: 5, kind: .usbOnly, link: .empty, cfg: .none,
    positionName: "Front, left")
check(StageLegend.rows(for: [usbStage]).isEmpty, "a USB-only receptacle never puts a line in the legend (§4.5)")
check(StageLegend.rows(for: [plain].map(cfg)).map(\.glyph) == [.segmented]
      && StageLegend.rows(for: [staleBare].map(cfg)).map(\.glyph) == [.emptySlot]
      && StageLegend.rows(for: [outside].map(cfg)).map(\.glyph) == [.doubleHairline]
      && StageLegend.rows(for: [managed].map(cfg)).map(\.glyph) == [.solidAccent]
      && StageLegend.rows(for: [drifted].map(cfg)).map(\.glyph) == [.dashed],
      "each legend line carries its own ring geometry")

// MARK: §4.8 — the callout quotes the row, verbatim.

let plainCallout = StageCalloutText(presentation: PortRowPresentation(snapshot: plain), showsTechnicalNames: false)
check(plainCallout.title == "Front, left", "callout title is the position name")
check(plainCallout.detail == "Nothing plugged in · In the Thunderbolt Bridge", "callout detail is the row's detail line")
check(plainCallout.technical == nil, "no technical line while technical names are off")
check(StageCalloutText(presentation: PortRowPresentation(snapshot: plain), showsTechnicalNames: true).technical
      == "en3 · bridge0", "the technical line is the row's suffix when technical names are on")
check(StageCalloutText(presentation: returnedRow, showsTechnicalNames: false).detail
      == "Back in the bridge · Nothing plugged in · In the Thunderbolt Bridge",
      "the returned row's three phrases come through with their middle dots")
check(StageCalloutText(presentation: PortRowPresentation(snapshot: addressed), showsTechnicalNames: false).detail
      == "Ready for RDMA · fe80::1c3d:5aff:fe22:9b04%en6", "the address goes on the end as the row draws it")
let usb = snapshot(port("", "Front, right", isThunderbolt: false), configuration: nil)
let usbCallout = StageCalloutText(presentation: PortRowPresentation(snapshot: usb), showsTechnicalNames: true)
check(usbCallout.title == "Front, right" && usbCallout.detail == "USB only — this one isn't Thunderbolt",
      "a USB-only receptacle's callout is its own subtitle, em dash and all")
check(usbCallout.technical == nil, "a USB-only receptacle has no technical line to add")
// The stage carries the same words, so the callout it draws cannot differ.
var stagePort = StagePort(port: plain.port, physicalIndex: 1, configuration: cfg(plain))
check(stagePort.callout(showsTechnicalNames: false) == nil, "no row quoted yet, no callout")
stagePort.calloutDetail = PortRowPresentation(snapshot: plain).detail.line
stagePort.technicalSuffix = PortRowPresentation(snapshot: plain).technicalSuffix
check(stagePort.callout(showsTechnicalNames: true) == StageCalloutText(
        title: "Front, left", detail: "Nothing plugged in · In the Thunderbolt Bridge", technical: "en3 · bridge0"),
      "the stage's callout is the row's presentation, word for word")

if failures > 0 {
    FileHandle.standardError.write(Data("test_presentation: \(failures) failed\n".utf8))
    exit(1)
}
print("test_presentation: all passed")
SWIFT

xcrun swiftc -swift-version 6 -warnings-as-errors \
  -I "$CORE_BIN" -L "$CORE_BIN" -lRDMALinkCore \
  -framework SystemConfiguration -framework IOKit -framework Security \
  -framework AppKit \
  -o "$WORK_DIR/test_presentation" \
  "$ROOT_DIR/App/Model/PortSnapshot.swift" \
  "$ROOT_DIR/App/Model/HubActions.swift" \
  "$ROOT_DIR/App/Model/NotesLocation.swift" \
  "$ROOT_DIR/App/Presentation/PortPresentation.swift" \
  "$ROOT_DIR/App/Presentation/ThisMacPresentation.swift" \
  "$ROOT_DIR/App/Presentation/OtherMacPresentation.swift" \
  "$ROOT_DIR/App/Flows/PreflightReport.swift" \
  "$ROOT_DIR/App/Flows/WizardRefusal.swift" \
  "$ROOT_DIR/App/Flows/WizardActions.swift" \
  "$ROOT_DIR/App/Presentation/RestorePresentation.swift" \
  "$ROOT_DIR/App/Stage/StageMath.swift" \
  "$ROOT_DIR/App/Stage/StageModel.swift" \
  "$ROOT_DIR/App/Stage/StageLegend.swift" \
  "$WORK_DIR/main.swift"

"$WORK_DIR/test_presentation"
# The same assertions under a French locale: §S1's sentences stay English.
"$WORK_DIR/test_presentation" -AppleLocale fr_FR -AppleLanguages "(fr)" >/dev/null
