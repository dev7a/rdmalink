#!/usr/bin/env bash
# Exercises the hub's pure presentation on its own: UX_SPEC §S1's ready row,
# the port rows, and what an undo note makes of a port (App/Model/PortSnapshot,
# App/Presentation/PortPresentation, App/Presentation/ThisMacPresentation) —
# §S3's first row, where R2 has to win over R1, and the Checked group's label
# (App/Flows/PreflightReport, with the two files its button row and refusal
# card reach into) — the set-up assistant's shape (App/Flows/SetUpFlow with
# the flow files under it): §2.3's step label counting this run's screens,
# §S4's choice made first and once, the frozen selection on S5, and §6.2 R7
# coming back to S5 — and §S8's subject (App/Presentation/OtherMacPresentation)
# — and the Restore sheet's
# button rows (App/Presentation/RestorePresentation), the only place §6.2's
# rows for R19, R20, R21, R28 and R30 are written down — and §4.8's two aids:
# the legend's rows from the stage's own ring decision (App/Stage/StageLegend,
# with App/Stage/StageModel and StageMath under it) and the callout's words
# from the row's presentation — and §6.2 R31's read-only hub: its headline
# and body over R23's, a footer with no button the model decides (§S1's `Quit`
# is the view's, on every hub state alike), and a stage with nothing to
# turn or select (App/Presentation/HubPresentation, with
# App/Presentation/ThunderboltGeneration under it for R23).
#
# The app target has no test bundle, and these files import nothing but
# Foundation, Observation, AppKit and RDMALinkCore, so — like script/test_stage_math.sh —
# they are compiled against the Core module `swift build` left behind and run
# as a plain executable. Every sentence asserted here is the spec's own.
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
check(text(returnedRow.detail.state) == "Returned by RDMALink", "returned row state")
check(returnedRow.detail.link.map(text) == "Nothing plugged in", "returned row keeps the link subtitle")
check(returnedRow.detail.membership.map(text) == "In the Thunderbolt Bridge",
      "returned row keeps the membership phrase")
check(returnedRow.detail.address == nil, "returned row has no address")
check(returnedRow.symbol == "arrow.uturn.backward.circle" && returnedRow.symbolStyle == .secondary,
      "returned row symbol")
check(returnedRow.actions == [.setItUpAgain(portID: "en5")], "returned row offers Set It Up Again only")
check(returnedRow.compactBadge == nil, "returned row has no Ready badge")
check(returnedRow.accessibilityLabel
      == "Back, far left. Thunderbolt port. Returned by RDMALink. Nothing plugged in. In the Thunderbolt Bridge.",
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
findings.notesWritability = .writable
findings.portsLoopedBack = [farLeft, farRight]
let looped = PreflightReport(findings)
check(looped.rows[0].state == .unsatisfied, "R2 row is unsatisfied")
check(looped.rows[0].finding.map(text)
      == "Both ends of one cable are in this Mac, on Back, far left and Back, far right. Unplug one end and put it in the other Mac.",
      "R2 row finding is §S3's")
check(looped.disabledReason.map(text) == "Unplug one end of that cable to continue.", "R2 disabled-button reason")
check(!looped.canProceed, "R2 disables S5's default button")
check(looped.attentionPortIDs == ["en5", "en6"], "R2 rings both ends of the cable")

// The same cable with both ends reading as linked Macs in one bridge — every
// input R1 has — is still R2, and rings R2's pair.
findings.portsWithAMac = [farLeft, farRight]
findings.portsInALoop = [farLeft, farRight]
let both = PreflightReport(findings)
check(both.rows[0].finding.map(text)?.hasPrefix("Both ends of one cable are in this Mac") == true,
      "R2 wins over R1")
check(both.disabledReason.map(text) == "Unplug one end of that cable to continue.", "R2 reason wins over R1's")

// Without the loop, the same two linked, bridged ports are R1.
findings.portsLoopedBack = []
let r1 = PreflightReport(findings)
check(r1.rows[0].finding.map(text)
      == "Two Macs are connected, on Back, far left and Back, far right. Unplug one and RDMALink will pick this back up.",
      "R1 row finding is §S3's")
check(r1.disabledReason.map(text) == "Unplug one of the two cables to continue.", "R1 disabled-button reason")
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
check(r2.watchingLine.map(text) == "RDMALink is watching — once this is sorted it carries straight on.",
      "R2 card keeps watching")
check(text(r2.headline) == "Both ends of that cable are in this Mac", "R2 card headline is §6.2's")

// MARK: §S8 — which port "this link" is, and when the far end has answered.

let linkedManaged = snapshot(
    port("en6", "Back, left middle", link: .macLinked), configuration: .readyForRDMA(serviceID: "MINE"),
    baseline: ownNote)
var addressed = linkedManaged
addressed.port.linkLocal = ["fe80::a2d1:73b4:9e0c:5f16"]
check(OtherMacReport(ports: [plain, outside]).subjectID == nil, "a Mac with no ready port has no subject")
check(OtherMacReport(ports: [plain, outside]).address == nil
      && !OtherMacReport(ports: [plain, outside]).answered, "and no address, and nothing has answered")
check(OtherMacReport(ports: [outside, managed]).subjectID == "en6",
      "a port set up outside RDMALink is never the subject; RDMALink's own is")
check(OtherMacReport(ports: [managed, addressed]).subjectID == "en6"
      && OtherMacReport(ports: [managed, addressed]).address == "fe80::a2d1:73b4:9e0c:5f16%en6",
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
check(titles(.undoNoteMissing) == ["Stop Managing This Port", "Copy These Steps", "Cancel", "Open Network Settings"],
      "R19: Open Network Settings (default) · Cancel · Copy These Steps · Stop Managing This Port")
check(titles(.notBackInBridge) == ["Copy These Steps", "Open Network Settings", "Cancel", "Try Again"],
      "R20: Try Again (default) · Cancel · Open Network Settings · Copy These Steps")
check(titles(.originalBridgeGone) == ["Leave Everything Alone", "Remove Service Only"],
      "R21: Remove Service Only · Leave Everything Alone")
// §2.6: a sheet's default is never an action that removes something the user
// didn't ask to remove, and the way out is Escape's, never Return's.
func defaultTitle(_ code: RefusalCode) -> String? {
    RestoreAction.defaultAction(in: RestoreRefusals.actions(for: code)).map { text($0.title) }
}
check(defaultTitle(.originalBridgeGone) == nil,
      "R21: no default — Remove Service Only is never pressed by Return")
check(defaultTitle(.createdServiceEdited) == nil,
      "R28: no default — Stop Managing… forgets the note a Restore needs")
check(RestoreAction.leaveEverythingAlone.isCancel && RestoreAction.cancel.isCancel
      && !RestoreAction.removeServiceOnly.isCancel,
      "Leave Everything Alone and Cancel are the sheet's Escape")
check(defaultTitle(.undoNoteMissing) == "Open Network Settings"
      && defaultTitle(.notBackInBridge) == "Try Again"
      && defaultTitle(.noteIsAReturnRecord) == "Set It Up Again",
      "every other row's default is §6.2's")
check(RestoreAction.defaultAction(in: [.copyDetails, .cancel]) == nil,
      "a row whose last button is Cancel has no default: Cancel is Escape's")
for code in [RefusalCode.volumeMounted, .undoNoteMissing, .notBackInBridge, .originalBridgeGone,
             .noBridgeToReturnTo, .createdServiceEdited, .noteIsAReturnRecord, .networkBusy,
             .credentialExpired] {
    // §2.6 and §6.1 rule 10: exactly one — never two, and never none, so the
    // way out is a button as well as Escape.
    check(RestoreRefusals.actions(for: code).filter(\.isCancel).count == 1,
          "every row has exactly one Escape button: \(code)")
}
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
      == "Returned by RDMALink · Nothing plugged in · In the Thunderbolt Bridge",
      "the returned row's three phrases come through with their middle dots")
check(StageCalloutText(presentation: PortRowPresentation(snapshot: addressed), showsTechnicalNames: false).detail
      == "Ready for RDMA · fe80::a2d1:73b4:9e0c:5f16%en6", "the address goes on the end as the row draws it")
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

// MARK: §6.2 R31 — an unrecognized Mac is read-only: the copy, the footer, the stage.

let unrecognized = HardwareModel(identifier: "Mac99,99", marketingName: "Mac", chip: "M9 Max",
                                 archetype: .unknown)
let studio = HardwareModel(identifier: "Mac15,14", marketingName: "Mac Studio", chip: "M3 Ultra",
                           archetype: .studioSix)
let r31 = HubPresentation.copy(hardware: unrecognized, ports: [managed, outside])
check(text(r31.headline) == "RDMALink doesn't recognize this Mac", "R31 headline is §6.2's")
check(text(r31.body)
      == "RDMALink only draws, and only changes, Macs it knows — and this isn't one of them. So there's no picture, and nothing here will be changed. The ports below are listed the way macOS reports them, and everything you see is real.",
      "R31 body is §6.2's, verbatim")
check(text(HubPresentation.copy(hardware: studio, ports: [managed]).headline) == "One port is ready for RDMA",
      "S1's own copy stands on a recognized Mac")
// R31 wins over R23: the generation table is keyed on the identifier, so a
// Thunderbolt 4 identifier can be listed there while the chassis is not.
let tb4Unrecognized = HardwareModel(identifier: "Mac16,1", marketingName: "MacBook Pro", chip: "M4",
                                    archetype: .unknown)
check(tb4Unrecognized.isThunderbolt4, "the fixture is Thunderbolt 4 by the table")
check(text(HubPresentation.copy(hardware: tb4Unrecognized, ports: []).headline) == "RDMALink doesn't recognize this Mac",
      "R31 wins over R23")
let tb4 = HardwareModel(identifier: "Mac16,1", marketingName: "MacBook Pro", chip: "M4", archetype: .notebook)
check(text(HubPresentation.copy(hardware: tb4, ports: []).headline) == "Nothing to configure here",
      "R23 stands on a recognized Thunderbolt 4 Mac")
let r31Footer = HubPresentation.footer(hardware: unrecognized, ports: [managed])
// §S1: R31's footer holds `Quit` and nothing else. `Quit` is neither the
// primary nor Restore — it is the same button on every hub state, so the view
// draws it unconditionally and the model has nothing to say about it. What
// the model must still refuse here is everything that writes.
check(r31Footer.primary == nil && !r31Footer.offersRestore,
      "R31: the footer offers neither the primary nor Restore…")
let tb4Footer = HubPresentation.footer(hardware: tb4, ports: [managed])
check(tb4Footer.primary == nil && tb4Footer.offersRestore, "R23: no primary, and Restore… stays")
let hubFooter = HubPresentation.footer(hardware: studio, ports: [managed])
check(hubFooter.primary == .setUpPort(portID: nil) && hubFooter.offersRestore
      && text(hubFooter.primaryTitle) == "Set Up Another Port…", "S1's footer on a recognized Mac")

// The stage: no chassis, so nothing to turn, select or light.
let stage = StageModel()
check(stage.picture == .pending && stage.chassis == nil && stage.relevantFaces.isEmpty,
      "before the identity lands there is nothing to draw")
stage.picture = .unrecognized
stage.ports = [StagePort(port: plain.port, physicalIndex: 1, configuration: cfg(plain))]
stage.select("en3")
check(stage.selectedID == nil, "R31: the rows take no selection")
check(stage.relevantFaces.isEmpty, "R31: no face selector")
stage.turnTo(.front)
stage.fit()
check(stage.narration == nil && stage.cameraRequest == nil,
      "R31: no camera move, and no \"Turning the Mac around\"")
stage.noteUnseenChange(on: .front)
check(stage.unseenChange == nil, "R31: no \"Something changed\" line for a face nobody can look at")
check(ReceptacleCatalogue.chassis(for: .unknown) == nil, "the catalogue has no chassis for an unrecognized Mac")
if let chassis = ReceptacleCatalogue.chassis(for: .studioSix) { stage.picture = .chassis(chassis) }
check(stage.chassis?.archetype == .studioSix, "a recognized Mac has its chassis")
stage.select("en3")
check(stage.selectedID == "en3", "and its rows select again")
check(stage.relevantFaces == [.back], "and the selector shows the faces that carry ports")

// MARK: §S3 — the Checked group's label follows how many rows said no.

var satisfied = PreflightFindings()
satisfied.mountedThunderboltVolumes = []
satisfied.route = .wiFi
satisfied.notesWritability = .writable
let allGood = PreflightReport(satisfied)
check(allGood.groupLabel.map(text)
      == "Checked: one cable, nothing mounted, another way in, room for the undo note.",
      "all four satisfied: the collapsed disclosure's one line")
check(!allGood.isExpanded && allGood.unsatisfiedCount == 0 && allGood.canProceed && allGood.disabledReason == nil,
      "all four satisfied: collapsed, and the default button is live")
var oneThing = satisfied
oneThing.portsWithAMac = [farLeft, farRight]
oneThing.portsInALoop = [farLeft, farRight]
let oneReport = PreflightReport(oneThing)
check(oneReport.groupLabel.map(text) == "Checked — one thing to sort out first", "one unsatisfied: §S3's label")
check(oneReport.isExpanded && oneReport.unsatisfiedCount == 1 && !oneReport.canProceed,
      "one unsatisfied: expanded, default button disabled")
var twoThings = oneThing
twoThings.mountedThunderboltVolumes = ["Vault"]
let twoReport = PreflightReport(twoThings)
check(twoReport.groupLabel.map(text) == "Checked — two things to sort out first", "two unsatisfied: §S3's label")
check(twoReport.unsatisfiedCount == 2 && twoReport.disabledReason.map(text) == "Unplug one of the two cables to continue.",
      "two unsatisfied: the first row's reason is the one printed")
let checking = PreflightReport(PreflightFindings())
check(checking.isChecking && checking.isExpanded && checking.groupLabel == nil && !checking.canProceed,
      "not observed yet: expanded, no label, and no claim")

// MARK: §2.3 band 1 — the label counts the screens of the current run.

check(text(WizardStep.choose.caption(openedOn: .choose)) == "Step 1 of 3", "picker run: choose is 1 of 3")
check(text(WizardStep.review.caption(openedOn: .choose)) == "Step 2 of 3", "picker run: review is 2 of 3")
check(text(WizardStep.apply.caption(openedOn: .choose)) == "Step 2 of 3", "picker run: setting up keeps review's label")
check(text(WizardStep.ready.caption(openedOn: .choose)) == "Step 3 of 3", "picker run: ready is 3 of 3")
check(text(WizardStep.review.caption(openedOn: .review)) == "Step 1 of 2", "chosen run: review is 1 of 2")
check(text(WizardStep.apply.caption(openedOn: .review)) == "Step 1 of 2", "chosen run: setting up keeps review's label")
check(text(WizardStep.ready.caption(openedOn: .review)) == "Step 2 of 2", "chosen run: ready is 2 of 2")

// MARK: §S4 — the choice is made at the beginning, and only once.

let farLeftPort = snapshot(port("en5", "Back, far left", bridges: [bridge0]),
                           configuration: .unconfigured(bridges: ["bridge0"]))
let leftMiddle = snapshot(port("en6", "Back, left middle", link: .macLinked, bridges: [bridge0]),
                          configuration: .unconfigured(bridges: ["bridge0"]))
let rightMiddle = snapshot(port("en7", "Back, right middle", link: .macLinked, bridges: [bridge0]),
                           configuration: .unconfigured(bridges: ["bridge0"]))
// A plan the way S5 gets one: Core's own preview over a world with nothing in
// the way. Read once here; the flow's planner hands it back.
let quietWorld = ObservedWorld(
    snapshot: InterfaceSnapshot(interfaces: []), services: [],
    context: PreflightContext(hardware: studio, observedPorts: [],
                              thunderboltBSDNames: ["en5", "en6", "en7"], primaryInterfaces: ["en0"]),
    rdma: .off)
let plannedFarLeft = SetUpPorts(ports: [OperationPort(farLeftPort.port)]).preview(world: quietWorld)
check(plannedFarLeft.canProceed && plannedFarLeft.buttonTitle == "Set Up Port", "the test plan can proceed")

@MainActor func settle(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// A flow whose planner answers with the plan above and whose runner — the
/// only thing that would ask for a password — answers as macOS does when the
/// dialog is dismissed. Nothing here can write.
@MainActor func makeFlow(ports: [PortSnapshot], findings: PreflightFindings = satisfied) -> SetUpFlow {
    let flow = SetUpFlow(
        planner: { _ in plannedFarLeft },
        runner: { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: NetworkConfigurationError.authorizationCancelled(-60006))
            }
        },
        finish: {})
    flow.update(ports: ports, hardware: studio, switchState: .unobserved, findings: findings)
    return flow
}

// A port chosen on the hub: the run opens on S5 and has two steps.
let fromHub = makeFlow(ports: [farLeftPort, leftMiddle])
fromHub.open(choosing: "en5")
check(fromHub.step == .review && fromHub.openedOn == .review, "hub choice: opens on review")
check(text(fromHub.backTitle) == "Back",
      "§2.3 band 4: a run that opens on S5 keeps Back — it goes to the picker, it doesn't leave")
check(text(fromHub.stepCaption) == "Step 1 of 2", "hub choice: Step 1 of 2")
check(fromHub.selection == ["en5"] && !fromHub.pickedForTheUser && fromHub.reviewPreSelectionLine == nil,
      "hub choice: the port is the one chosen, and nobody picked for the user")
check(fromHub.isSelectionFrozen && fromHub.frozenSelection == ["en5"], "hub choice: the choice is frozen on S5")

// Nothing chosen and exactly one port with a Mac on the end: picked for the
// user, opens on S5, says so, and Back is the picker — which the run then counts.
let picked = makeFlow(ports: [farLeftPort, leftMiddle])
picked.open(choosing: nil)
check(picked.step == .review && picked.selection == ["en6"] && picked.pickedForTheUser, "pre-selection: opens on review")
check(picked.reviewPreSelectionLine.map(text)
      == "RDMALink has picked Back, left middle for you, because that's the port with another Mac on the end of it. Choose a different one if you'd rather.",
      "pre-selection: §S4's line is stated on S5")
check(text(picked.stepCaption) == "Step 1 of 2", "pre-selection: Step 1 of 2")
picked.goBack()
check(text(picked.backTitle) == "Cancel",
      "§2.3 band 4: on the picker the leading button leaves the assistant, so it reads Cancel")
check(picked.step == .choose && picked.openedOn == .choose && picked.selection == ["en6"] && !picked.pickedForTheUser,
      "Back from S5 is the picker, with the selection intact and now the user's")
check(text(picked.stepCaption) == "Step 1 of 3", "back on the picker: Step 1 of 3")
picked.goForward()
check(picked.step == .review && text(picked.stepCaption) == "Step 2 of 3" && picked.reviewPreSelectionLine == nil,
      "continuing from the picker: Step 2 of 3, and no pre-selection line")

// §S5's line is the reason for the pick that was made. A second Mac arriving
// while S5 is up is the Checked group's news (R1), not a new sentence on a
// screen where nothing can be chosen.
let pickedThenAnother = makeFlow(ports: [farLeftPort, leftMiddle])
pickedThenAnother.open(choosing: nil)
let reasonAtOpen = pickedThenAnother.reviewPreSelectionLine.map(text)
pickedThenAnother.update(ports: [farLeftPort, leftMiddle, rightMiddle], hardware: studio,
                         switchState: .unobserved, findings: oneThing)
check(pickedThenAnother.step == .review && pickedThenAnother.selection == ["en6"]
      && pickedThenAnother.reviewPreSelectionLine.map(text) == reasonAtOpen
      && pickedThenAnother.choose.preSelectionLine.map(text) != reasonAtOpen,
      "a second Mac arrives on S5: the pre-selection line stays the reason for the pick")
check(pickedThenAnother.checks.unsatisfiedCount == 1 && pickedThenAnother.checks.isExpanded,
      "…and the Checked group carries R1")

// Nothing chosen and no candidate, or two: the run opens on the picker.
let noCandidate = makeFlow(ports: [farLeftPort])
noCandidate.open(choosing: nil)
check(text(noCandidate.backTitle) == "Cancel", "a run that opens on the picker: Cancel, not Back")
noCandidate.beginIdentify()
check(text(noCandidate.backTitle) == "Cancel", "§S4b: Identify keeps its own Cancel")
noCandidate.cancelIdentify()
check(noCandidate.step == .choose && noCandidate.selection.isEmpty && text(noCandidate.stepCaption) == "Step 1 of 3",
      "no Mac on any port: opens on choose")
let twoCandidates = makeFlow(ports: [farLeftPort, leftMiddle, rightMiddle])
twoCandidates.open(choosing: nil)
check(twoCandidates.step == .choose && twoCandidates.selection.isEmpty && !twoCandidates.pickedForTheUser,
      "two Macs on the end: opens on choose, nothing picked")
check(twoCandidates.choose.preSelectionLine.map(text)
      == "Two ports have a Mac on the end. RDMALink hasn't picked for you — choose the one with the cable you mean.",
      "two candidates: the picker says why it didn't pick")
check(twoCandidates.primary?.isEnabled == false, "nothing chosen: Continue is disabled")

// A port in hand that S4 would route elsewhere gets S4 and the same answer.
let routed = makeFlow(ports: [farLeftPort, managed])
routed.open(choosing: "en6")
check(routed.step == .choose && routed.selection.isEmpty && routed.routingLine.map(text)
      == "This one's already a link. Want to see how it's doing?", "an already-ready port in hand: the picker, and R27's line")

// MARK: §S4 — after the picker the choice is frozen, on the flow and on the stage.

fromHub.select("en6")
fromHub.extendSelection("en6")
check(fromHub.selection == ["en5"], "a click on S5 leaves the flow's selection alone")
let frozenStage = StageModel()
if let chassis = ReceptacleCatalogue.chassis(for: .studioSix) { frozenStage.picture = .chassis(chassis) }
frozenStage.ports = [farLeftPort, leftMiddle].enumerated().map {
    StagePort(port: $1.port, physicalIndex: $0 + 1, configuration: cfg($1))
}
frozenStage.freezeSelection(on: ["en5"])
check(frozenStage.isSelectionFrozen && frozenStage.selectedID == "en5", "the stage holds the chosen receptacle")
check(frozenStage.frozenSelection == ["en5"], "the list dims by the frozen set: one chosen, one other")
frozenStage.select("en6")
check(frozenStage.selectedID == "en5", "a click on S5 leaves the stage's selection alone")
frozenStage.hover("en6")
check(frozenStage.hoveredID == nil, "no hover glow while the choice is frozen")
frozenStage.thawSelection()
check(!frozenStage.isSelectionFrozen && frozenStage.frozenSelection.isEmpty, "thawed: nothing is held")
frozenStage.select("en6")
check(frozenStage.selectedID == "en6", "choosing again: the stage takes clicks once more")
// Two ports chosen (§S4's ⌘-click): both are chosen, so neither is "the
// others" — the list dims by the set while the model lights the first.
frozenStage.freezeSelection(on: ["en5", "en6"])
check(frozenStage.frozenSelection == ["en5", "en6"] && frozenStage.selectedID == "en5",
      "a two-port run: both held, the first in physical order lit")
frozenStage.thawSelection()

// §S5 3D: "unselected receptacles fade to 25 %, so the scene shows the subject
// and its context and nothing else". The same 25 % holds through S6 (the
// camera is locked) and S7 (the configured receptacle keeps its solid ring).
// §4.5's USB hover dim is the hub's, and the freeze is not on there.
let usbOnly = snapshot(port("", "Front, left", isThunderbolt: false), configuration: nil)
let dimStage = StageModel()
if let chassis = ReceptacleCatalogue.chassis(for: .studioSix) { dimStage.picture = .chassis(chassis) }
dimStage.ports = [farLeftPort, leftMiddle, usbOnly].enumerated().map {
    StagePort(port: $1.port, physicalIndex: $0 + 1, configuration: cfg($1))
}
@MainActor func dims(_ model: StageModel) -> [Float] {
    let moment = model.moment()
    return moment.ports.map { moment.dim(for: $0) }
}
check(dims(dimStage) == [1, 1, 1], "nothing frozen: the whole machine is drawn at full strength")
dimStage.hover("Front, left")
check(dims(dimStage) == [1, 1, StageMoment.usbHoverDim],
      "§4.5: a hovered USB-only receptacle dims 15 %, and nothing else moves")
dimStage.hover(nil)
dimStage.freezeSelection(on: ["en5"])
check(dims(dimStage) == [1, StageMoment.frozenDim, StageMoment.frozenDim],
      "§S5: the chosen receptacle holds; every other one fades to 25 %, USB included")
dimStage.freezeSelection(on: ["en5", "en6"])
check(dims(dimStage) == [1, 1, StageMoment.frozenDim],
      "a two-port run: both chosen receptacles hold — the second is the subject too")
// §S3: "When a check names a port, that receptacle takes a 1.5 pt attention
// ring" — and with two Macs "both receptacles ring simultaneously and a faint
// light thread leaves each one, making the loop visible rather than described".
// R1 on S5 is exactly that: one of the two ports is the frozen choice and the
// other is not, and fading the one the user has been told to unplug would put
// out the light the sentence is pointing at.
dimStage.freezeSelection(on: ["en5"])
dimStage.attention(ids: ["en6"])
check(dims(dimStage) == [1, 1, StageMoment.frozenDim],
      "§S3 outranks §S5: a receptacle a check names is drawn in full, freeze or no freeze")
dimStage.attention(ids: [])
check(dims(dimStage) == [1, StageMoment.frozenDim, StageMoment.frozenDim],
      "…and it fades again the moment the check is satisfied")
dimStage.thawSelection()
check(dims(dimStage) == [1, 1, 1], "thaw puts every receptacle back")
check(dimStage.moment().frozenSelection == nil,
      "a thawed moment says 'not frozen' rather than 'frozen on nothing'")

// MARK: §S4 — the picker's rows: dimmed, with the explanatory subtitle.

// "The port list is in full density and every row is a selection target;
// non-selectable rows are dimmed with an explanatory subtitle."
func picker(_ snapshot: PortSnapshot) -> PortRowPresentation {
    PortRowPresentation(snapshot: snapshot, mode: .picker)
}
let foreign = snapshot(port("en8", "Front, right"),
                       configuration: .foreign(serviceID: "THEIRS", reason: .staticIPv4Address))
check(ChoosePortReport.route(for: managed) == .alreadyReady
      && ChoosePortReport.route(for: adopted) == .alreadyReady
      && ChoosePortReport.route(for: outside) == .adopt
      && ChoosePortReport.route(for: usbOnly) == .usbPort
      && ChoosePortReport.route(for: foreign) == .foreignService,
      "the routes the picker dims by")
check(ChoosePortReport.route(for: plain) == nil && ChoosePortReport.route(for: returned) == nil
      && ChoosePortReport.route(for: drifted) == nil,
      "…and the three that simply select")

check(picker(managed).isDimmed && text(picker(managed).detail.state) == "Already ready for RDMA"
      && picker(managed).detail.address == nil && picker(managed).detail.membership == nil,
      "§S4: an already-ready row is dimmed and reads Already ready for RDMA, and nothing else")
check(picker(managed).actions == [.restore(portID: "en6")],
      "§S4: …and offers Restore…")
check(picker(adopted).isDimmed && text(picker(adopted).detail.state) == "Already ready for RDMA",
      "an adopted row is dimmed and reads the same sentence")
check(picker(adopted).actions
      == [.returnToBridge(portID: "en7"), .stopManaging(portID: "en7")],
      "…and keeps the hub's buttons: §S4's Restore… is not a thing an adopted note can offer, and its click's question has to have somewhere to answer")
check(picker(outside).isDimmed && text(picker(outside).detail.state) == "Set up outside RDMALink",
      "§S4: a hand-configured row is dimmed and reads Set up outside RDMALink")
check(picker(outside).actions == [.adopt(portID: "en2")],
      "§S4: …and keeps Adopt…, the one route on this screen that reaches S9 — Return to Bridge… goes")
check(picker(usbOnly).isDimmed
      && text(picker(usbOnly).detail.state) == "USB only — this one isn't Thunderbolt"
      && picker(usbOnly).actions.isEmpty,
      "§S4: the USB sentence is the picker's too, and a USB row has no button on either screen")
check(picker(foreign).isDimmed
      && text(picker(foreign).detail.state) == text(PortRowPresentation(snapshot: foreign).detail.state),
      "R16's row is dimmed but keeps the hub's subtitle: §S4 has no sentence for it")

// §6.2 R16 on the picker: `Choose Another Port` puts the card away and leaves
// the user choosing. Only `Cancel` leaves the assistant (§2.3 band 4).
var r16LeftTheAssistant = false
let r16 = SetUpFlow(
    planner: { _ in plannedFarLeft },
    runner: { _ in AsyncThrowingStream { $0.finish() } },
    finish: { r16LeftTheAssistant = true })
r16.update(ports: [farLeftPort, foreign], hardware: studio, switchState: .unobserved, findings: satisfied)
r16.open(choosing: nil)
r16.select("en8")
check(r16.step == .choose && r16.refusal?.code == "R16", "R16: a click on a foreign static-IPv4 port raises R16 on the picker")
r16.chooseAnotherPort()
check(r16.step == .choose && r16.refusal == nil && !r16LeftTheAssistant,
      "R16: Choose Another Port puts the card away and stays on the picker")
r16.goBack()
check(r16LeftTheAssistant, "…where Cancel is what leaves the assistant")

// A selectable row is the hub's row, untouched: §S4's selectable subtitles are
// §S1's, and the screen is still a picker for it.
for selectable in [plain, returned, drifted] {
    let row = picker(selectable)
    let hub = PortRowPresentation(snapshot: selectable)
    check(!row.isDimmed && row.detail == hub.detail && row.actions == hub.actions,
          "a selectable row on the picker is the row the hub draws: \(selectable.port.positionName)")
}
// And every row off the picker is the hub's, dimmed rows included.
check(PortRowPresentation(snapshot: managed).isDimmed == false
      && text(PortRowPresentation(snapshot: managed).detail.state)
          == "Ready for RDMA · the address appears when a Mac arrives",
      "the hub's own already-ready row is untouched")
check(picker(managed).accessibilityLabel
      == "Back, left middle. Thunderbolt port. Already ready for RDMA.",
      "§8.2: VoiceOver reads the picker's row, not the hub's")
// §4.8: the callout quotes "the row's title and detail line, verbatim", so the
// receptacle says what the row beside it says on this screen too. `StageInput`
// carries the mode for exactly this (App/Model/StageBinding.swift).
check(StageCalloutText(presentation: picker(managed), showsTechnicalNames: false).detail
      == "Already ready for RDMA",
      "§4.8: the callout over a dimmed receptacle quotes the picker's row, not the hub's")
check(PortRowMode(step: .choose) == .picker
      && PortRowMode(step: .review) == .status && PortRowMode(step: .apply) == .status
      && PortRowMode(step: .ready) == .status && PortRowMode(step: nil) == .status,
      "§S4: the picker is S4 and nothing else — the hub and the frozen steps are status")

// MARK: §S5 — a check that said no disables the button; a refusal removes it.

await settle { fromHub.reviewPlan != nil }
check(fromHub.reviewPlan != nil, "the plan landed")
check(fromHub.primary.map { text($0.title) } == "Set Up Port" && fromHub.primary?.isEnabled == true,
      "all four satisfied: Set Up Port, live")
fromHub.update(ports: [farLeftPort, leftMiddle], hardware: studio, switchState: .unobserved, findings: oneThing)
check(fromHub.primary.map { text($0.title) } == "Set Up Port" && fromHub.primary?.isEnabled == false,
      "R1: the default button is disabled, not removed")
check(fromHub.disabledReason.map(text) == "Unplug one of the two cables to continue.", "R1: the reason above the separator")
check(fromHub.reviewRefusal == nil && fromHub.checks.isExpanded, "R1: no card; the Checked group expands")
check(fromHub.attentionPortIDs == ["en5", "en6"], "R1: the two receptacles ring on S5")
fromHub.update(ports: [farLeftPort, leftMiddle], hardware: studio, switchState: .unobserved, findings: satisfied)
await settle { fromHub.primary?.isEnabled == true }
check(fromHub.primary?.isEnabled == true && fromHub.disabledReason == nil, "the cable goes: the button is live again, no click")

// MARK: §6.2 R7 — no permission given: back on S5 with the selection intact.

fromHub.goForward()
check(fromHub.apply != nil && fromHub.isAuthorizing && fromHub.step == .review,
      "Set Up Port asks straight away, with S5 still the screen showing")
check(fromHub.primary?.isEnabled == false && !fromHub.showsBack, "while the dialog is up nothing else can be pressed")
await settle { fromHub.apply == nil }
check(fromHub.refusal?.code == "R7" && fromHub.reviewRefusal?.code == "R7", "the dialog dismissed: R7")
check(fromHub.step == .review && fromHub.selection == ["en5"] && fromHub.isSelectionFrozen,
      "R7: still on S5, selection intact")
check(fromHub.primary == nil && fromHub.showsBack, "R7: the card's Try Again is the default; Back stays")
fromHub.tryAgain()
check(fromHub.refusal == nil && fromHub.apply == nil && fromHub.step == .review && fromHub.selection == ["en5"],
      "Try Again: back to S5 proper with the selection intact, nothing asked yet")
check(fromHub.reviewPlan != nil && fromHub.primary.map { text($0.title) } == "Set Up Port"
      && fromHub.primary?.isEnabled == true,
      "…and the default button is live again")
fromHub.goForward()
check(fromHub.apply != nil && fromHub.isAuthorizing, "Set Up Port asks again")
await settle { fromHub.apply == nil }
check(fromHub.refusal?.code == "R7", "and macOS can say no again")
fromHub.goBack()
check(fromHub.step == .choose && fromHub.refusal == nil && fromHub.selection == ["en5"],
      "Back from R7 is the picker, selection intact")

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
  "$ROOT_DIR/App/Presentation/ThunderboltGeneration.swift" \
  "$ROOT_DIR/App/Presentation/HubPresentation.swift" \
  "$ROOT_DIR/App/Presentation/OtherMacPresentation.swift" \
  "$ROOT_DIR/App/Flows/PreflightReport.swift" \
  "$ROOT_DIR/App/Flows/WizardRefusal.swift" \
  "$ROOT_DIR/App/Flows/WizardActions.swift" \
  "$ROOT_DIR/App/Flows/WizardStep.swift" \
  "$ROOT_DIR/App/Flows/ChoosePortReport.swift" \
  "$ROOT_DIR/App/Flows/ReadyReport.swift" \
  "$ROOT_DIR/App/Flows/ReviewPreview.swift" \
  "$ROOT_DIR/App/Flows/IdentifySession.swift" \
  "$ROOT_DIR/App/Flows/ApplyRun.swift" \
  "$ROOT_DIR/App/Flows/SetUpFlow.swift" \
  "$ROOT_DIR/App/Presentation/RestorePresentation.swift" \
  "$ROOT_DIR/App/Stage/StageMath.swift" \
  "$ROOT_DIR/App/Stage/StageModel.swift" \
  "$ROOT_DIR/App/Stage/StageLegend.swift" \
  "$WORK_DIR/main.swift"

"$WORK_DIR/test_presentation"
# The same assertions under a French locale: §S1's sentences stay English.
"$WORK_DIR/test_presentation" -AppleLocale fr_FR -AppleLanguages "(fr)" >/dev/null
