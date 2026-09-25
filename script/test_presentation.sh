#!/usr/bin/env bash
# Exercises the hub's pure presentation on its own: UX_SPEC §S1's ready row,
# the port rows, and what an undo note makes of a port (App/Model/PortSnapshot,
# App/Presentation/PortPresentation, App/Presentation/ThisMacPresentation) —
# §S3's first row, where R2 has to win over R1, and the Checked group's label
# (App/Flows/PreflightReport, with the two files its button row and refusal
# card reach into) — the set-up assistant's shape (App/Flows/SetUpFlow with
# the flow files under it): §2.3's step label counting this run's screens,
# §S4's choice made first and once, the frozen selection on S5, and §6.2 R7
# coming back to S5 — and §S8's subject (App/Presentation/OtherMacPresentation):
# the port a run just set up, or the Help menu's ready selection, with the
# stage's handoff receding every other port and the legend naming the ghost,
# and the `Other Mac:` pop-up — its items, the default, the catalogue model
# each family is drawn as and the far port on it (App/Stage/StageChassisGeometry)
# — and the Restore sheet's
# button rows (App/Presentation/RestorePresentation), the only place §6.2's
# rows for R19, R20, R21, R28 and R30 are written down — and §4.8's two aids:
# the legend's rows from the stage's own ring decision (App/Stage/StageLegend,
# with App/Stage/StageModel and StageMath under it) and the callout's words
# from the row's presentation — and §6.2 R31's read-only hub: its headline
# and body over R23's, a footer with no button the model decides (§S1's `Quit`
# is the view's, on every hub state alike), and a stage with nothing to
# turn or select (App/Presentation/HubPresentation, with
# App/Presentation/ThunderboltGeneration under it for R23) — and the hub's one
# door (App/Model/HubActionsModel, with the Adopt and change-log presentation
# it reads): nothing re-enters a run while the assistant is up (§2.7), and
# every set-up goes through the footer's terms (§S1) — and §S6's quit that
# waits for a burst to land (App/Model/BurstGate), exercised with a reply the
# test counts, never with a write.
#
# The app target has no test bundle, and these files import nothing but
# Foundation, Observation, AppKit, CoreGraphics and RDMALinkCore, so — like script/test_stage_math.sh —
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
check(returnedRow.actions == [.setUpAgain(portID: "en5")], "returned row offers Set Up Again… only")
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
check(PortRowPresentation(snapshot: staleBare).actions
      == [.setUpPort(portID: "en5"), .returnToBridge(portID: "en5")],
      "a bare port out of every bridge carries Set Up…, then Return to Bridge…")
check(text(PortRowPresentation(snapshot: staleBare).detail.state) == "Nothing plugged in"
      && PortRowPresentation(snapshot: staleBare).detail.membership.map(text) == "Not in any bridge",
      "and reads the plain subtitle")
// Out of the bridge with a near match: plain with Adopt… — and never drift.
let staleNear = snapshot(
    port("en5", "Back, far left"),
    configuration: .nearMatch(serviceID: "HAND", differences: [.ipv4NotOff(method: "DHCP")]), baseline: returnRecord)
check(staleNear.readiness == .plain, "a return record is never drift")
check(PortRowPresentation(snapshot: staleNear).actions
      == [.adopt(portID: "en5"), .returnToBridge(portID: "en5")],
      "a near match offers Adopt… and the return, and no Set Up…: Core routes it to Adopt")

// MARK: §7.5: any port out of every bridge can be put back, bare or not.

check(snapshot(port("en2", "Back, far right"), configuration: .unconfigured(bridges: [])).isOutOfEveryBridge,
      "a bare port out of every bridge")
check(PortRowPresentation(snapshot: snapshot(port("en2", "Back, far right"),
                                             configuration: .unconfigured(bridges: []))).actions
      == [.setUpPort(portID: "en2"), .returnToBridge(portID: "en2")], "carries Set Up… and Return to Bridge…")
check(!plain.isOutOfEveryBridge && PortRowPresentation(snapshot: plain).actions == [.setUpPort(portID: "en3")],
      "§S1: a bridge member that has never been set up carries Set Up… alone")
check(PortRowPresentation(snapshot: snapshot(port("en2", "Back, far right", bridges: [bridge0]),
                                             configuration: nil)).actions
      == [.setUpPort(portID: "en2")],
      "a port whose configuration could not be read is still one the picker takes: Core's review decides")
check(!snapshot(port("en2", "Back, far right"), configuration: nil).isOutOfEveryBridge,
      "a configuration that could not be read is not out of every bridge")
check(PortRowPresentation(snapshot: snapshot(port("", "Front, right", isThunderbolt: false),
                                             configuration: nil)).actions.isEmpty,
      "a USB-only receptacle carries nothing, Set Up… included")
// §S1 "Copy — buttons": the row already names the port, so it reads Set Up…;
// the footer and the Port menu keep Set Up Port….
check(text(HubAction.setUpPort(portID: "en3").rowTitle) == "Set Up…"
      && text(HubAction.setUpPort(portID: "en3").title) == "Set Up Port…"
      && text(HubAction.setUpPort(portID: nil).title) == "Set Up Port…",
      "a row's set-up button reads Set Up…; everywhere else it is Set Up Port…")
for action in [HubAction.adopt(portID: "en2"), .restore(portID: "en6"), .returnToBridge(portID: "en2"),
               .stopManaging(portID: "en7"), .setUpAgain(portID: "en5")] {
    check(text(action.rowTitle) == text(action.title), "every other row button reads as it does anywhere: \(action.id)")
}
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
check(PortRowPresentation(snapshot: drifted).actions == [.setUpAgain(portID: "en6")],
      "drift row action: Set Up Again…, and no Set Up… beside it")
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

// The Help menu with nothing selected: §S8's own rule, over ready ports only.
func fromHelp(_ ports: [PortSnapshot], selected: String? = nil) -> OtherMacReport {
    OtherMacReport(ports: ports, origin: .help(selected: selected))
}
let linkedManaged = snapshot(
    port("en6", "Back, left middle", link: .macLinked), configuration: .readyForRDMA(serviceID: "MINE"),
    baseline: ownNote)
var addressed = linkedManaged
addressed.port.linkLocal = ["fe80::a2d1:73b4:9e0c:5f16"]
check(fromHelp([plain, outside]).subjectID == nil, "a Mac with no ready port has no subject")
check(fromHelp([plain, outside]).address == nil
      && !fromHelp([plain, outside]).answered, "and no address, and nothing has answered")
check(fromHelp([outside, managed]).subjectID == "en6",
      "a port set up outside RDMALink is never the subject; RDMALink's own is")
check(fromHelp([managed, addressed]).subjectID == "en6"
      && fromHelp([managed, addressed]).address == "fe80::a2d1:73b4:9e0c:5f16%en6",
      "the first ready port with an address is the subject, and step 4 names it whole")
check(fromHelp([managed]).address == nil, "a ready port with no address yet has none to name")
check(fromHelp([adopted]).subjectID == "en7", "an adopted port is RDMALink's to hand out")
check(!fromHelp([managed]).answered, "nothing plugged in has not answered")
check(fromHelp([linkedManaged]).answered, "a Mac at the far end has answered")
check(!fromHelp([snapshot(port("en6", "Back, left middle", link: .macLinkComingUp),
                          configuration: .readyForRDMA(serviceID: "MINE"), baseline: ownNote)]).answered,
      "a link still coming up has not answered yet")

// The report that raised this: Back, far left just set up with nothing in it,
// while Front, left and Front, right are ready, linked and addressed. The
// handoff was drawn from Front, left and step 4 printed Front, left's address.
func readyNote(_ bsdName: String, _ receptacle: Int, _ positionName: String) -> PortBaseline {
    PortBaseline(
        bsdName: bsdName, receptacle: receptacle, positionName: positionName,
        bridges: [BridgeMembership(bridgeName: "bridge0", members: [bsdName], isActive: true)],
        createdService: CreatedServiceRecord(identifier: "MINE-\(bsdName)", interfaceBSDName: bsdName))
}
func readyPort(_ bsdName: String, _ receptacle: Int, _ positionName: String, linkedAt address: String? = nil)
    -> PortSnapshot {
    var ready = snapshot(
        port(bsdName, positionName, link: address == nil ? .empty : .macLinked),
        configuration: .readyForRDMA(serviceID: "MINE-\(bsdName)"),
        baseline: readyNote(bsdName, receptacle, positionName))
    ready.port.linkLocal = address.map { [$0] } ?? []
    return ready
}
let justSetUp = readyPort("en5", 1, "Back, far left")
let frontLeft = readyPort("en7", 5, "Front, left", linkedAt: "fe80::1c2b:3d4e:5f60:7182")
let frontRight = readyPort("en8", 6, "Front, right", linkedAt: "fe80::9a8b:7c6d:5e4f:3a2b")
let userRig = [justSetUp, frontLeft, frontRight]
check(userRig.ready.map(\.id) == ["en5", "en7", "en8"], "the rig: three ready ports, in physical order")
let afterRun = OtherMacReport(ports: userRig, origin: .run(setUp: "en5"))
check(afterRun.subjectID == "en5",
      "§S8 from S7: the port the run just set up is the subject, not a ready neighbour with an address")
check(afterRun.address == nil,
      "…so step 4 names no other port's address: this link has none yet, and says it appears when a Mac arrives")
check(!afterRun.answered,
      "…and a Mac answering on Front, left is not this link answering")
check(OtherMacReport(ports: userRig, origin: .run(setUp: "en7")).address == "fe80::1c2b:3d4e:5f60:7182%en7"
      && OtherMacReport(ports: userRig, origin: .run(setUp: "en7")).answered,
      "a run whose port is linked names that port's own address, and its far end answering counts")
var rereading = justSetUp
rereading.configuration = nil
check(OtherMacReport(ports: [rereading, frontLeft], origin: .run(setUp: "en5")).subjectID == "en5",
      "a run's port stays the subject through a reading that could not see its configuration")
check(OtherMacReport(ports: [frontLeft, frontRight], origin: .run(setUp: "en5")).subjectID == "en7",
      "a run's port this Mac no longer reports falls back to §S8's own rule")
check(fromHelp(userRig).subjectID == "en7",
      "§S8 from the Help menu with nothing selected: the first ready port with an address")
check(fromHelp(userRig, selected: "en5").subjectID == "en5" && fromHelp(userRig, selected: "en5").address == nil,
      "§S8 from the Help menu: the selected port, when it is ready, even with no address yet")
check(fromHelp(userRig, selected: "en8").subjectID == "en8"
      && fromHelp(userRig, selected: "en8").address == "fe80::9a8b:7c6d:5e4f:3a2b%en8",
      "…and step 4 names the selected port's own address")
check(fromHelp([outside, frontLeft], selected: "en2").subjectID == "en7"
      && fromHelp([plain, frontLeft], selected: "en3").subjectID == "en7"
      && fromHelp([frontLeft, frontRight], selected: "en5").subjectID == "en7",
      "a selected port set up outside RDMALink, not ready, or not reported gives way to §S8's own rule")

// MARK: §6.2's button rows in the Restore sheet, laid out by §2.6's one rule:
// the default trailing with Cancel just before it, or Cancel trailing when a
// row has no default.

func titles(_ code: RefusalCode, overTheAssistant: Bool = false) -> [String] {
    RestoreRefusals.actions(for: code, overTheAssistant: overTheAssistant).map { text($0.title) }
}
check(titles(.undoNoteMissing) == ["Stop Managing…", "Copy These Steps", "Cancel", "Open Network Settings"],
      "R19/L4: Open Network Settings (default) · Cancel · Copy These Steps · Stop Managing…")
check(RestoreAction.stopManaging.title == HubAction.stopManaging(portID: "en6").title,
      "L4: R19's, R28's and R30's Stop Managing… is the Port menu's command under its own name")
check(titles(.notBackInBridge) == ["Copy These Steps", "Open Network Settings", "Cancel", "Try Again"],
      "R20: Try Again (default) · Cancel · Open Network Settings · Copy These Steps")
check(titles(.originalBridgeGone) == ["Remove Service Only", "Cancel"],
      "R21/L6: Remove Service Only · Cancel, Cancel trailing with no default")
// §2.6: a sheet's default is never an action that removes something the user
// didn't ask to remove, and the way out is Escape's, never Return's.
func defaultTitle(_ code: RefusalCode) -> String? {
    RestoreAction.defaultAction(in: RestoreRefusals.actions(for: code)).map { text($0.title) }
}
check(defaultTitle(.originalBridgeGone) == nil,
      "R21: no default — Remove Service Only is never pressed by Return")
check(defaultTitle(.createdServiceEdited) == nil,
      "R28: no default — Stop Managing… forgets the note a Restore needs")
check(RestoreAction.allCases.filter(\.isCancel) == [.cancel],
      "L6: Cancel is the one word for leaving a sheet before anything happens")
check(defaultTitle(.undoNoteMissing) == "Open Network Settings"
      && defaultTitle(.notBackInBridge) == "Try Again"
      && defaultTitle(.noteIsAReturnRecord) == "Set Up Again…",
      "every other row's default is §6.2's")
// L6: §2.6's order holds in every row — the default trailing with Cancel just
// before it, or Cancel trailing with no default — over the picker as well.
for code in [RefusalCode.volumeMounted, .undoNoteMissing, .notBackInBridge, .originalBridgeGone,
             .noBridgeToReturnTo, .createdServiceEdited, .noteIsAReturnRecord, .networkBusy,
             .credentialExpired, .macNotRecognized] {
    for over in [false, true] {
        for setUpAgain in [false, true] {
            let row = RestoreRefusals.actions(for: code, offersSetUpAgain: setUpAgain, overTheAssistant: over)
            let cancel = row.firstIndex(of: .cancel)
            let hasDefault = RestoreAction.defaultAction(in: row) != nil
            check(cancel == (hasDefault ? row.count - 2 : row.count - 1),
                  "L6: Cancel sits just before the default, or trailing with none: \(code) over=\(over)")
        }
    }
}
check(titles(.createdServiceEdited, overTheAssistant: true) == ["Cancel", "Open Network Settings"]
      && RestoreAction.defaultAction(in: RestoreRefusals.actions(
        for: .createdServiceEdited, overTheAssistant: true)) == .openNetworkSettings,
      "R28 over the picker: no Stop Managing…, and Open Network Settings is the default")
check(RestoreRefusals.actions(for: .noteIsAReturnRecord, offersSetUpAgain: false) == [.stopManaging, .cancel]
      && RestoreAction.defaultAction(in: [.stopManaging, .cancel]) == nil,
      "R30 without the row's set-up action: Stop Managing… · Cancel, no default, Cancel trailing")
// L5: the stop-managing form's own row — its committer the default, unless
// the note is the port's only way back.
check(RestoreAction.formRow(committer: .confirmStopManaging, isDefault: true) == [.cancel, .confirmStopManaging]
      && RestoreAction.defaultAction(in: RestoreAction.formRow(
        committer: .confirmStopManaging, isDefault: true)) == .confirmStopManaging,
      "the stop-managing form over an adopted note: Stop Managing is the default, Cancel before it")
check(RestoreAction.formRow(committer: .confirmStopManaging, isDefault: false) == [.confirmStopManaging, .cancel]
      && RestoreAction.defaultAction(in: RestoreAction.formRow(
        committer: .confirmStopManaging, isDefault: false)) == nil,
      "L5: over a note that records bridges it has no default, and Cancel is trailing")
check(text(RestoreAction.confirmStopManaging.title) == "Stop Managing"
      && text(RestoreAction.stopManaging.title) == "Stop Managing…",
      "L4: the opener has the ellipsis and the committer does not")
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
check(titles(.createdServiceEdited) == ["Stop Managing…", "Open Network Settings", "Cancel"],
      "R28/L6: Stop Managing… · Open Network Settings · Cancel, Cancel trailing, and no Copy Details")
check(titles(.noteIsAReturnRecord) == ["Stop Managing…", "Cancel", "Set Up Again…"],
      "R30: Set Up Again… (default) · Stop Managing… · Cancel, drawn with Cancel before the default")
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

// §4.8 and §S8: the line that names the ghost, only while the handoff is up.
let legendStage = StageModel()
if let chassis = ReceptacleCatalogue.chassis(for: .studioSix) { legendStage.picture = .chassis(chassis) }
legendStage.ports = [plain, managed].enumerated().map {
    StagePort(port: $1.port, physicalIndex: $0 + 1, configuration: cfg($1))
}
@MainActor func legend(_ model: StageModel) -> [String] {
    StageLegend.rows(for: model.ports, handoff: model.handoff).map { text($0.label) }
}
check(legend(legendStage) == ["In a bridge", "Ready for RDMA"], "no handoff: rings only, nothing names a ghost")
legendStage.beginHandoff(for: "en6")
check(legend(legendStage) == ["In a bridge", "Ready for RDMA", "The other Mac"],
      "§S8's handoff up: one line joins the rings, last — The other Mac")
check(StageLegend.rows(for: legendStage.ports, handoff: legendStage.handoff).last?.glyph == .ghost,
      "…glyph first, a small faint box")
legendStage.beginHandoff(for: nil)
check(legend(legendStage).last == "The other Mac",
      "the ghost is named whether or not the handoff has a near port to draw its line from")
legendStage.endHandoff()
check(legend(legendStage) == ["In a bridge", "Ready for RDMA"], "the line goes when the ghost does")

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
// The 2026 rows, read 2026-09-25: Apple names one chip per identifier, and
// the specs pages name the generation per chip.
// Each fixture is the catalogue's own row: its name and chip as Apple gives
// them, its archetype read back from the identifier table.
func catalogued(_ identifier: String, _ marketingName: String, _ chip: String) -> HardwareModel? {
    HardwareModel.archetype(forIdentifier: identifier).map {
        HardwareModel(identifier: identifier, marketingName: marketingName, chip: chip, archetype: $0)
    }
}
let m6Mini = catalogued("Mac18,5", "Mac mini", "M6")
check(m6Mini?.archetype == .mini && m6Mini?.isThunderbolt4 == true
      && m6Mini.map { text(HubPresentation.copy(hardware: $0, ports: []).headline) } == "Nothing to configure here",
      "R23: the Mac mini (M6) has Thunderbolt 4 ports and opens read-only")
let tb5Rows = [
    catalogued("Mac17,14", "Mac Studio", "M5 Max"),
    catalogued("Mac17,15", "Mac Studio", "M5 Ultra"),
    catalogued("Mac17,16", "Mac mini", "M5 Pro"),
]
check(tb5Rows.map { $0?.archetype } == [.studioFour, .studioSix, .mini]
      && tb5Rows.allSatisfy { $0?.thunderboltGeneration == .five },
      "the Mac Studio (M5 Max), (M5 Ultra) and the Mac mini (M5 Pro) are Thunderbolt 5")
check(HardwareModel(identifier: "Mac16,10", marketingName: "Mac mini", chip: "M4", archetype: .mini)
          .thunderboltGeneration == .unknown,
      "the Mac mini (2024) page lists its two identifiers together, so the table still says nothing for the M4")
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
      && text(hubFooter.primary!.title) == "Set Up Port…",
      "L3: S1's footer on a recognized Mac reads Set Up Port… with a port ready, as the Port menu's ⌘N does")
check(text(HubPresentation.footer(hardware: studio, ports: [plain]).primary!.title) == "Set Up Port…",
      "L3: …and with none ready: one command, one name")

// §S1: a row's set-up button — Set Up… or Set Up Again…, and the drift
// situation row's Set Up Again… — is the footer's Set Up Port… for one port,
// on the same terms. Every other button is not the footer's to answer.
let setUpActions: [HubAction] = [.setUpPort(portID: nil), .setUpPort(portID: "en3"), .setUpAgain(portID: "en5")]
let otherActions: [HubAction] = [.adopt(portID: "en2"), .restore(portID: "en6"), .returnToBridge(portID: "en2"),
                                 .stopManaging(portID: "en7"), .showMe(portID: "en6")]
check(setUpActions.allSatisfy(\.opensSetUp) && !otherActions.contains(where: \.opensSetUp),
      "Set Up Port…, Set Up… and Set Up Again… are the ways into set-up, and nothing else is")
check(text(HubAction.setUpAgain(portID: "en5").title) == "Set Up Again…"
      && text(HubAction.setUpAgain(portID: "en5").rowTitle) == "Set Up Again…",
      "L2: Set Up Again… opens the assistant, so it carries the ellipsis, on a row as anywhere")
check(setUpActions.allSatisfy { hubFooter.offers($0) && hubFooter.allows($0) },
      "S1: on an ordinary hub every set-up button is there and live")
let twoMacsFooter = HubPresentation.footer(hardware: studio, ports: [
    snapshot(port("en5", "Back, far left", link: .macLinked, bridges: [bridge0]),
             configuration: .unconfigured(bridges: ["bridge0"])),
    snapshot(port("en6", "Back, left middle", link: .macLinked, bridges: [bridge0]),
             configuration: .unconfigured(bridges: ["bridge0"])),
])
check(twoMacsFooter.primary != nil && !twoMacsFooter.isPrimaryEnabled
      && twoMacsFooter.disabledReason.map(text) == "Unplug one of the two cables to set up a port.",
      "L3: the two-Macs fixture is R1's footer, and its reason says what waits on the cable")
check(setUpActions.allSatisfy { twoMacsFooter.offers($0) && !twoMacsFooter.allows($0) },
      "R1: Set Up… and Set Up Again… are disabled with the footer's primary, never one without the other")
for footer in [tb4Footer, r31Footer] {
    check(setUpActions.allSatisfy { !footer.offers($0) && !footer.allows($0) },
          "R23 and R31: every set-up button is absent with the footer's primary")
}
for footer in [hubFooter, twoMacsFooter, tb4Footer, r31Footer] {
    check(otherActions.allSatisfy { footer.offers($0) && footer.allows($0) },
          "every other row button is its row's answer alone, whatever the footer says")
}

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
/// dialog is dismissed. Nothing here can write: a runner is a stream of
/// values the test writes itself, and no test runner opens a session.
@MainActor func makeFlow(
    ports: [PortSnapshot],
    findings: PreflightFindings = satisfied,
    planner: @escaping SetUpFlow.Planner = { _ in plannedFarLeft },
    runner: @escaping ApplyRun.Runner = { _ in
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NetworkConfigurationError.authorizationCancelled(-60006))
        }
    },
    finish: @escaping @MainActor () -> Void = {}
) -> SetUpFlow {
    let flow = SetUpFlow(planner: planner, runner: runner, finish: finish)
    flow.update(ports: ports, hardware: studio, switchState: .unobserved, findings: findings)
    return flow
}

/// Leaving the assistant, counted per flow.
@MainActor final class Exits {
    var count = 0
    func leave() { count += 1 }
}

// N2: a control that names its port — a row's Set Up…, the drift row, the
// change log, R30, a double-click — opens Review, step 1 of 2, and the run has
// no picker in it. Its first screen's leading button is Cancel, and Cancel
// returns to where the run started.
let namedExits = Exits()
let fromHub = makeFlow(ports: [farLeftPort, leftMiddle], finish: { namedExits.leave() })
fromHub.open(.port("en5"))
check(fromHub.step == .review && fromHub.openedOn == .review, "a named port: opens on review")
check(text(fromHub.stepCaption) == "Step 1 of 2", "a named port: Step 1 of 2")
check(text(fromHub.backTitle) == "Cancel",
      "§2.3 band 4: Review is this run's first screen, so the leading button reads Cancel")
check(fromHub.selection == ["en5"] && !fromHub.pickedForTheUser, "the port is the one named; nobody picked for the user")
check(fromHub.isSelectionFrozen && fromHub.frozenSelection == ["en5"], "the choice is frozen on S5")
check(fromHub.presence == .underWay, "§2.7: S5 is under way — the Port menu offers nothing")

// N1: the footer and ⌘N always open the picker, step 1 of 3. With exactly one
// port with a Mac on the end, RDMALink picks it and the picker says why.
let picked = makeFlow(ports: [farLeftPort, leftMiddle])
picked.open(.choose(suggested: nil))
check(picked.step == .choose && picked.openedOn == .choose && picked.selection == ["en6"] && picked.pickedForTheUser,
      "the footer: the picker, with the one port with a Mac chosen")
check(text(picked.stepCaption) == "Step 1 of 3" && text(picked.backTitle) == "Cancel",
      "…as step 1 of 3, Cancel leading")
check(picked.choose.preSelectionLine.map(text)
      == "RDMALink has picked Back, left middle for you, because that's the port with another Mac on the end of it. Choose a different one if you'd rather.",
      "…and the picker states the reason for the pick")
check(picked.primary?.isEnabled == true, "…and Continue is live at once")
check(picked.presence == .picker(routed: nil), "§2.7: the picker is the one screen the Port menu still offers something on")
picked.goForward()
check(picked.step == .review && text(picked.stepCaption) == "Step 2 of 3" && text(picked.backTitle) == "Back",
      "Continue: Review is step 2 of 3, and Back leads — there is a step before it")
picked.goBack()
check(picked.step == .choose && picked.openedOn == .choose && picked.selection == ["en6"]
      && text(picked.stepCaption) == "Step 1 of 3",
      "N3: Back moves between steps — the picker, the selection intact, and the count never changes")
check(picked.choose.preSelectionLine != nil, "…RDMALink's pick is still the selection, so its reason still stands")
picked.select("en5")
check(picked.choose.preSelectionLine == nil && !picked.pickedForTheUser,
      "§S4: the line goes the moment the user chooses")
picked.select("en6")
check(picked.choose.preSelectionLine == nil && !picked.pickedForTheUser,
      "…and never comes back: a port the user chose is theirs, even RDMALink's")

// N1: the hub's selection comes with the picker when set-up can take it — the
// user chose it, so there is no line — and otherwise RDMALink's pick does.
let suggested = makeFlow(ports: [farLeftPort, leftMiddle])
suggested.open(.choose(suggested: "en5"))
check(suggested.step == .choose && suggested.selection == ["en5"] && !suggested.pickedForTheUser
      && suggested.choose.preSelectionLine == nil,
      "the hub's selection opens the picker chosen, with no line")
let suggestedOutside = makeFlow(ports: [farLeftPort, leftMiddle, outside])
suggestedOutside.open(.choose(suggested: "en2"))
check(suggestedOutside.step == .choose && suggestedOutside.selection == ["en6"] && suggestedOutside.pickedForTheUser,
      "a hub selection set-up can't take is not chosen: RDMALink's pick is, with its reason")

// Nothing chosen and no candidate, or two: the picker with nothing chosen.
let noCandidate = makeFlow(ports: [farLeftPort])
noCandidate.open(.choose(suggested: nil))
check(text(noCandidate.backTitle) == "Cancel", "a run that opens on the picker: Cancel, not Back")
noCandidate.beginIdentify()
check(text(noCandidate.backTitle) == "Cancel" && noCandidate.presence == .underWay,
      "§S4b: Identify keeps its own Cancel, and the Port menu offers nothing over it")
noCandidate.cancelIdentify()
check(noCandidate.step == .choose && noCandidate.selection.isEmpty && text(noCandidate.stepCaption) == "Step 1 of 3",
      "no Mac on any port: the picker, nothing chosen")
let twoCandidates = makeFlow(ports: [farLeftPort, leftMiddle, rightMiddle])
twoCandidates.open(.choose(suggested: nil))
check(twoCandidates.step == .choose && twoCandidates.selection.isEmpty && !twoCandidates.pickedForTheUser,
      "two Macs on the end: the picker, nothing picked")
check(twoCandidates.choose.preSelectionLine.map(text)
      == "Two ports have a Mac on the end. RDMALink hasn't picked for you — choose the one with the cable you mean.",
      "two candidates: the picker says why it didn't pick")
check(twoCandidates.primary?.isEnabled == false, "nothing chosen: Continue is disabled")
twoCandidates.select("en7")
check(twoCandidates.choose.preSelectionLine == nil, "§S4: the two-candidates line only while nothing is chosen")

// §S4: a picker's dimmed row routes; its line states a fact and names the
// row's own button (§6.2 R27).
let routed = makeFlow(ports: [farLeftPort, managed])
routed.open(.choose(suggested: nil))
routed.select("en6")
check(routed.step == .choose && routed.selection.isEmpty && routed.routingLine.map(text)
      == "This one's already a link. Restore… puts it back.", "an already-ready port clicked: R27's line, and no selection")
check(routed.presence == .picker(routed: "en6"),
      "§2.7: the row a click routed is the one the Port menu's Restore… means on the picker")
routed.select("en5")
check(routed.routingLine == nil && routed.presence == .picker(routed: nil),
      "…until the user chooses a port, when the line and the routed row go together")

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
// §S8: "The line is that port's cable, so exactly one link reads — this port
// to the other Mac": every other receptacle recedes to 25 %, and no
// receptacle draws its own thread while the line is up.
dimStage.beginHandoff(for: "en6")
check(dims(dimStage) == [StageMoment.frozenDim, 1, StageMoment.frozenDim],
      "§S8: the near port holds; every other receptacle recedes to 25 %, USB included")
check(dimStage.moment().handoffHoldsTheOnlyLink,
      "§S8: while the line is up it is the only link drawn — every thread stands down, the near port's and its neighbours'")
check(dimStage.selectedID == "en6",
      "§S8: that port becomes the selection as the handoff opens, so the list and the stage agree (§2.4)")
// A row click, a click on the model, or the Port menu's Restore… (whose sheet
// "turns to the port and rings it") selects another port while §S8 is up.
dimStage.select("en5")
check(dims(dimStage) == [1, 1, StageMoment.frozenDim],
      "§S8: a receptacle the user selects while the screen is up comes forward, as a selection does")
check(dimStage.handoff?.portID == "en6" && dimStage.moment().handoffHoldsTheOnlyLink,
      "…and the line stays this link's, with no thread come back")
dimStage.beginHandoff(for: nil)
check(dims(dimStage) == [1, 1, 1] && !dimStage.moment().handoffHoldsTheOnlyLink,
      "§S8 with no near port: no line, nothing singled out, nothing recedes, every thread stays")
check(dimStage.selectedID == "en5", "…and the selection stays where it was")
dimStage.endHandoff()
check(dims(dimStage) == [1, 1, 1] && dimStage.handoff == nil && !dimStage.moment().handoffHoldsTheOnlyLink,
      "the handoff over, every receptacle and every thread is back")

// MARK: §S8 "The other Mac's picture" — the Other Mac: pop-up and what it draws.

check(OtherMacChoice.standard == .anyMac, "§S8: Any Mac is the default")
check(OtherMacChoice.allCases == [.anyMac, .macBookPro, .macStudio, .macMini],
      "§S8: four items, in the spec's order")
check(OtherMacChoice.allCases.map { text($0.title) } == ["Any Mac", "MacBook Pro", "Mac Studio", "Mac mini"],
      "§S8: each item verbatim")
check(OtherMacChoice.allCases.allSatisfy { !text($0.title).hasSuffix("…") && !text($0.title).hasSuffix("...") },
      "§1.3 rule 11: choosing an item finishes the command, so none ends in an ellipsis")
check(OtherMacChoice.allCases.map(\.rawValue) == ["anyMac", "macBookPro", "macStudio", "macMini"],
      "the remembered values are the ones every earlier launch wrote")
check(OtherMacChoice.anyMac.representative == nil && OtherMacChoice.anyMac.archetype == nil,
      "§S8: Any Mac draws the featureless box")
check(OtherMacChoice.macBookPro.representative == "Mac17,7"
      && OtherMacChoice.macBookPro.archetype == .notebook,
      "§S8: MacBook Pro is drawn as the 14-inch MacBook Pro (M5 Pro or M5 Max), from the catalogue")
check(OtherMacChoice.macStudio.representative == "Mac17,14"
      && OtherMacChoice.macStudio.archetype == .studioFour,
      "§S8: Mac Studio is drawn as the Mac Studio (M5 Max), from the catalogue")
check(OtherMacChoice.macMini.representative == "Mac17,16"
      && OtherMacChoice.macMini.archetype == .mini,
      "§S8: Mac mini is drawn as the Mac mini (M5 Pro), from the catalogue")

// §S8: the line ends on "that model's Thunderbolt port nearest this Mac on the
// face a cable usually goes into — the back of a Mac Studio or a Mac mini, the
// left side of a MacBook Pro".
@MainActor func ghostEnd(_ archetype: Archetype) -> (PortFace?, String?) {
    let chassis = ReceptacleCatalogue.chassis(for: archetype)
    return (chassis?.usualCableFace, chassis?.ghostPort?.positionName)
}
check(ghostEnd(.studioFour) == (.back, "Back, far left") && ghostEnd(.studioSix) == (.back, "Back, far left"),
      "§S8: a Mac Studio takes the line on the back, far left — the port nearest this Mac")
check(ghostEnd(.mini) == (.back, "Back, left"), "§S8: a Mac mini takes it on the back, left")
check(ghostEnd(.notebook) == (.left, "Left side, rear"), "§S8: a MacBook Pro takes it on the left side, rear")
check([Archetype.studioFour, .studioSix, .mini, .notebook].allSatisfy {
          ReceptacleCatalogue.chassis(for: $0)?.ghostPort?.kind == .thunderbolt
      }, "§S8: the far port is always a Thunderbolt port, never a USB-only one")
check(OtherMacChoice.allCases.allSatisfy { choice in
          choice.archetype.map { ReceptacleCatalogue.chassis(for: $0)?.ghostPort != nil } ?? true
      }, "every family the pop-up offers has a chassis and a far port to draw")

// The stage: a pick is part of the handoff, redraws the ghost in place, and
// frames the new pair as the handoff first did — leaving the user's
// selection where it is.
let pickStage = StageModel()
if let chassis = ReceptacleCatalogue.chassis(for: .studioSix) { pickStage.picture = .chassis(chassis) }
pickStage.ports = [farLeftPort, leftMiddle].enumerated().map {
    StagePort(port: $1.port, physicalIndex: $0 + 1, configuration: cfg($1))
}
pickStage.beginHandoff(for: "en6", ghost: OtherMacChoice.macMini.archetype)
check(pickStage.handoff == StageHandoff(portID: "en6", face: .back, ghost: .mini),
      "§S8: the handoff carries what the ghost is drawn as")
check(pickStage.cameraRequest?.kind == .handoff(.back, ghost: .mini),
      "…and the camera frames the pair with that Mac in it")
check(pickStage.selectedID == "en6", "…with the near port selected as the handoff opens")
pickStage.cameraRequestHandled()
pickStage.select("en5")
pickStage.cameraRequestHandled()
pickStage.beginHandoff(for: "en6", ghost: OtherMacChoice.macBookPro.archetype)
check(pickStage.handoff?.ghost == .notebook && pickStage.handoff?.portID == "en6",
      "§S8: a new pick redraws the ghost, and the line stays this link's")
check(pickStage.selectedID == "en5", "…leaving the user's selection where they put it")
check(pickStage.cameraRequest?.kind == .handoff(.back, ghost: .notebook),
      "…and the camera frames the new pair as the handoff first did")
pickStage.cameraRequestHandled()
pickStage.beginHandoff(for: "en6", ghost: .notebook)
check(pickStage.cameraRequest == nil, "the same pick again moves nothing")
pickStage.beginHandoff(for: "en6", ghost: OtherMacChoice.anyMac.archetype)
check(pickStage.handoff == StageHandoff(portID: "en6", face: .back, ghost: nil)
      && pickStage.cameraRequest?.kind == .handoff(.back, ghost: nil),
      "§S8: Any Mac puts the box back")
check(StageLegend.rows(for: pickStage.ports, handoff: pickStage.handoff).last.map { text($0.label) }
      == "The other Mac",
      "§4.8: the legend's line keeps its words whatever the ghost is drawn as")
pickStage.beginHandoff(for: "en6", ghost: .mini)
check(StageLegend.rows(for: pickStage.ports, handoff: pickStage.handoff).last.map { text($0.label) }
      == "The other Mac" && StageLegend.rows(for: pickStage.ports, handoff: pickStage.handoff).last?.glyph == .ghost,
      "…and its small faint box")
pickStage.endHandoff()

// MARK: §S4 — the picker's rows: dimmed, with the explanatory subtitle.

// "The port list is in full density and every row is a selection target;
// non-selectable rows are dimmed with an explanatory subtitle."
func picker(_ snapshot: PortSnapshot) -> PortRowPresentation {
    PortRowPresentation(snapshot: snapshot, mode: .picker)
}
let foreign = snapshot(port("en8", "Front, right"),
                       configuration: .foreign(serviceID: "THEIRS", reason: .staticIPv4Address))
// The service RDMALink made, since given a manual address: Core calls the
// configuration R16's, but the service is RDMALink's own, edited since.
let driftedForeign = snapshot(port("en6", "Back, left middle"),
                              configuration: .foreign(serviceID: "MINE", reason: .staticIPv4Address),
                              baseline: ownNote)
// And a new service made by hand with a manual address, over the same note.
let driftedForeignOther = snapshot(port("en6", "Back, left middle"),
                                   configuration: .foreign(serviceID: "HAND", reason: .staticIPv4Address),
                                   baseline: ownNote)
// And the same service switched to DHCP: a near match, and still drift.
let driftedNear = snapshot(port("en6", "Back, left middle"),
                           configuration: .nearMatch(serviceID: "MINE", differences: [.ipv4NotOff(method: "DHCP")]),
                           baseline: ownNote)
check(driftedForeign.readiness == .drifted && driftedForeign.hasRDMALinksOwnServiceEdited
      && ChoosePortReport.route(for: driftedForeign) == .editedService
      && driftedNear.readiness == .drifted && ChoosePortReport.route(for: driftedNear) == .editedService,
      "§S1: RDMALink's own service edited since routes to Restore…, a fixed IPv4 address or a near match alike — never R16's 'It isn't RDMALink's'")
check(driftedForeignOther.readiness == .drifted && !driftedForeignOther.hasRDMALinksOwnServiceEdited
      && ChoosePortReport.route(for: driftedForeignOther) == .foreignService,
      "…while a fixed IPv4 address on a service RDMALink didn't make is R16's")
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
check(picker(adopted).actions == [.returnToBridge(portID: "en7")],
      "…and offers the route §S4 names for an adopted one, Return to Bridge… — it has no exact Restore (§7.3)")
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
check(PortRowPresentation(snapshot: foreign).actions == [.returnToBridge(portID: "en8")]
      && picker(foreign).actions.isEmpty,
      "R16's row carries no Set Up… on the hub, and nothing on the picker: its card is the answer, and no second sheet opens over the assistant (§2.6)")

// §S1: every Thunderbolt port that can be set up carries exactly one set-up
// button on its hub row — Set Up… if it has never been set up, Set Up
// Again… if its setup has gone or was returned. A ready port, and a port that
// has never been set up but has a service of its own, carries neither.
func setUpButtons(_ row: PortRowPresentation) -> [HubAction] {
    row.actions.filter(\.opensSetUp)
}
for settable in [plain, staleBare, returned, drifted] {
    check(setUpButtons(PortRowPresentation(snapshot: settable)).count == 1,
          "a port set-up can take has exactly one set-up button: \(settable.port.positionName)")
}
for unsettable in [managed, adopted, outside, staleMatch, staleNear, usbOnly, foreign] {
    check(setUpButtons(PortRowPresentation(snapshot: unsettable)).isEmpty,
          "a port set-up can't take has none: \(unsettable.port.positionName) (\(unsettable.readiness))")
}
// A drifted row keeps its one Set Up Again… — except a drifted port with a
// service of its own (S6, §S1), which Core would route to Adopt or refuse and
// never plan: RDMALink's own service edited since offers Restore… (R28), a
// new near match made by hand Adopt…, and R16's fixed address nothing.
check(PortRowPresentation(snapshot: driftedForeign).actions == [.restore(portID: "en6")],
      "§S1: RDMALink's own service given a fixed IPv4 address since offers Restore… (R28), never Set Up Again…")
check(PortRowPresentation(snapshot: driftedForeignOther).actions.isEmpty,
      "§S1, §S4: a drifted row over R16's fixed address on a hand-made service offers nothing — set-up can't take it")
check(PortRowPresentation(snapshot: driftedNear).actions == [.restore(portID: "en6")],
      "S6: a drifted near match over RDMALink's own service offers Restore…, never Set Up Again…")
let driftedNearOther = snapshot(port("en6", "Back, left middle"),
                                configuration: .nearMatch(serviceID: "HAND", differences: [.ipv4NotOff(method: "DHCP")]),
                                baseline: ownNote)
check(driftedNearOther.readiness == .drifted && !driftedNearOther.hasRDMALinksOwnServiceEdited
      && ChoosePortReport.route(for: driftedNearOther) == .adopt
      && PortRowPresentation(snapshot: driftedNearOther).actions == [.adopt(portID: "en6")],
      "S6: a drifted near match over a new service made by hand offers Adopt…")
check(picker(driftedNear).isDimmed && picker(driftedNear).actions == [.restore(portID: "en6")]
      && picker(driftedNearOther).isDimmed && picker(driftedNearOther).actions == [.adopt(portID: "en6")],
      "…and the picker dims both and names the same route")
check(text(picker(driftedNear).detail.state) == "Not set up any more"
      && text(picker(driftedNearOther).detail.state) == "Set up outside RDMALink",
      "…RDMALink's own keeps its hub subtitle; a hand-made one reads Set up outside RDMALink")
// The drift situation row's first button is the row's own, and its detail
// line is only printed while it is true.
let driftSituation = Situation.drift(drifted)
check(driftSituation.actions == [.setUpAgain(portID: "en6"), .stopManaging(portID: "en6")]
      && driftSituation.detail != nil,
      "L5: the drift row: Set Up Again… and Stop Managing…, the service gone")
check(driftSituation.actions.map { text($0.title) } == ["Set Up Again…", "Stop Managing…"],
      "L5: the drift row's second button opens S10's stop-managing form, so it carries the ellipsis")
let editedSituation = Situation.drift(driftedNear)
check(editedSituation.actions == [.restore(portID: "en6"), .stopManaging(portID: "en6")]
      && editedSituation.detail == nil,
      "S6: a drifted near match's situation row offers the row's Restore…, and never says a service that is there is gone")
check(Situation.drift(driftedNearOther).actions == [.adopt(portID: "en6"), .stopManaging(portID: "en6")]
      && Situation.drift(driftedNearOther).detail != nil,
      "…and a new service made by hand: Adopt…, and RDMALink's service really is gone")
check(Situation.drift(driftedForeign).actions == [.restore(portID: "en6"), .stopManaging(portID: "en6")]
      && Situation.drift(driftedForeign).detail == nil,
      "§S1: the drift row over RDMALink's own service given a fixed address: Restore…, and no claim that it is gone")
check(Situation.drift(driftedForeignOther).actions == [.stopManaging(portID: "en6")]
      && Situation.drift(driftedForeignOther).detail != nil,
      "§S1: …and over R16's hand-made service, only Stop Managing… — never a Set Up Again… into a refusal")

// §S1's "configurable" receptacle: the stage's double-click asks the row's own
// question, so a receptacle never starts a set-up its row would not offer.
for takes in [plain, staleBare, returned, drifted,
              snapshot(port("en2", "Back, far right", bridges: [bridge0]), configuration: nil)] {
    check(PortRowPresentation.offersSetUp(takes),
          "set-up takes \(takes.port.positionName) (\(takes.readiness))")
}
for refuses in [managed, adopted, outside, staleMatch, staleNear, usbOnly, foreign, driftedForeign,
                driftedForeignOther, driftedNear] {
    check(!PortRowPresentation.offersSetUp(refuses),
          "set-up never takes \(refuses.port.positionName) (\(refuses.readiness)), so neither does a double-click")
}

// §6.2 R16 on the picker: `Choose Another Port` puts the card away and leaves
// the user choosing. Only `Cancel` leaves the assistant (§2.3 band 4).
var r16LeftTheAssistant = false
let r16 = SetUpFlow(
    planner: { _ in plannedFarLeft },
    runner: { _ in AsyncThrowingStream { $0.finish() } },
    finish: { r16LeftTheAssistant = true })
r16.update(ports: [farLeftPort, foreign], hardware: studio, switchState: .unobserved, findings: satisfied)
r16.open(.choose(suggested: nil))
r16.select("en8")
check(r16.step == .choose && r16.refusal?.code == "R16", "R16: a click on a foreign static-IPv4 port raises R16 on the picker")
r16.chooseAnotherPort()
check(r16.step == .choose && r16.refusal == nil && !r16LeftTheAssistant,
      "R16: Choose Another Port puts the card away and stays on the picker")
r16.goBack()
check(r16LeftTheAssistant, "…where Cancel is what leaves the assistant")

// A selectable row keeps the hub's words — §S4's selectable subtitles are
// §S1's — but none of its buttons: choosing the row is the action (§S4).
for selectable in [plain, returned, drifted] {
    let row = picker(selectable)
    let hub = PortRowPresentation(snapshot: selectable)
    check(!row.isDimmed && row.detail == hub.detail && row.actions.isEmpty,
          "a selectable row on the picker has the hub's words and no button: \(selectable.port.positionName)")
}
check(picker(staleBare).actions.isEmpty,
      "…a bare port out of every bridge included: no Set Up…, no Return to Bridge…")
check(picker(staleNear).isDimmed && picker(staleNear).actions == [.adopt(portID: "en5")]
      && text(picker(staleNear).detail.state) == "Set up outside RDMALink",
      "S6: a near match is not selectable on the picker — Core would route it to Adopt — and keeps Adopt… alone")
check(PortRowPresentation(snapshot: returned).actions == [.setUpAgain(portID: returned.id)]
      && PortRowPresentation(snapshot: drifted).actions == [.setUpAgain(portID: drifted.id)]
      && PortRowPresentation(snapshot: plain).actions == [.setUpPort(portID: plain.id)],
      "…while the hub offers Set Up Again… on those rows, and Set Up… on the one never set up")
for dimmed in [managed, adopted, outside, usbOnly, foreign, driftedForeign, driftedForeignOther, driftedNear] {
    check(picker(dimmed).isDimmed && !picker(dimmed).actions.contains(where: \.opensSetUp),
          "a dimmed row on the picker never carries Set Up… or Set Up Again…: \(dimmed.port.positionName) (\(dimmed.readiness))")
}
check(picker(driftedForeign).actions == [.restore(portID: "en6")]
      && text(picker(driftedForeign).detail.state) == "Not set up any more",
      "§S4: RDMALink's own service given a fixed address is dimmed, keeps its hub subtitle and names Restore…")
check(picker(driftedForeignOther).actions.isEmpty,
      "§S4: R16 over a drifted note keeps none of the hub's buttons — its answer is the card")
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
check(fromHub.primary == nil && fromHub.showsBack && text(fromHub.backTitle) == "Cancel",
      "R7: the card's Try Again is the default; the footer's Cancel stays")
check(fromHub.reviewRefusal?.actions == [.tryAgain],
      "N5: R7's card never repeats the footer's way out — no Back, no Cancel")
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
check(namedExits.count == 0, "nothing so far has left the assistant")
fromHub.goBack()
check(namedExits.count == 1,
      "N3: Cancel from R7 in a run that opened on S5 leaves the assistant — there is no picker it never had")


// MARK: S1 — nothing re-enters a run (§2.6, §2.7).

@MainActor func hubModel(_ ports: [PortSnapshot], hardware: HardwareModel = studio) -> HubActionsModel {
    let hub = HubActionsModel()
    hub.ports = ports
    hub.hardware = hardware
    hub.footer = HubPresentation.footer(hardware: hardware, ports: ports)
    return hub
}

let onTheHub = hubModel([farLeftPort, managed, outside, adopted])
check(onTheHub.assistant == nil && onTheHub.canPerform(.setUpPort(portID: nil))
      && onTheHub.canPerform(.changeLog) && onTheHub.canPerform(.restore(portID: "en6"))
      && onTheHub.canPerform(.stopManaging(portID: "en7")),
      "S1: on the hub the Port menu offers what there is to act on")
let overPicker = hubModel([farLeftPort, managed, outside, adopted])
overPicker.assistant = .picker(routed: nil)
for refused in [HubAction.setUpPort(portID: nil), .setUpPort(portID: "en5"), .setUpAgain(portID: "en5"),
                .restoreAll, .changeLog, .stopManaging(portID: "en7"), .returnToBridge(portID: "en2"),
                .stopManaging(portID: "en6")] {
    check(!overPicker.canPerform(refused), "S1: nothing re-enters a run from the picker: \(refused.id)")
}
check(overPicker.canPerform(.identifyPort(portID: nil)),
      "S1, N8: on the picker the Port menu's Identify Port… is live — it starts S4b")
check(overPicker.canPerform(.restore(portID: "en6")) && overPicker.canPerform(.returnToBridge(portID: "en7"))
      && overPicker.canPerform(.adopt(portID: "en2")) && !overPicker.canPerform(.restore(portID: "en7")),
      "S1: …and a dimmed row's own route, Restore… or Adopt…, is the one sheet that may open over it")
check(!overPicker.canPerform(.adopt(portID: "en6")) && !overPicker.canPerform(.restore(portID: "en5")),
      "…never a route the picker doesn't name for that row, and nothing for a row it lets you choose")
check(overPicker.menuPortID == nil && overPicker.restoreOnePort == nil
      && !overPicker.canPerform(overPicker.restoreAction),
      "§2.7: with no row routed, the Port menu's Restore… and Adopt… have nothing to mean")
overPicker.assistant = .picker(routed: "en6")
check(overPicker.menuPortID == "en6" && overPicker.restoreOnePort == .restore(portID: "en6")
      && overPicker.canPerform(.restore(portID: "en6")),
      "§2.7: once a dimmed row is clicked, the Port menu's Restore… means that row")
overPicker.assistant = .underWay
for refused in [HubAction.identifyPort(portID: nil), .restore(portID: "en6"), .adopt(portID: "en2"),
                .setUpPort(portID: nil), .changeLog, .restoreAll] {
    check(!overPicker.canPerform(refused), "S1: on S4b to S7 the Port menu offers nothing: \(refused.id)")
}
check(overPicker.menuPortID == nil, "…and means no port")
overPicker.perform(.setUpPort(portID: nil))
overPicker.perform(.changeLog)
check(overPicker.pendingSetUp == nil && !overPicker.showsChangeLog,
      "S1: the hub's one door refuses a second run, and the change log, while a run is under way")
overPicker.assistant = .picker(routed: nil)
overPicker.perform(.identifyPort(portID: nil))
check(overPicker.pendingIdentify && overPicker.pendingSetUp == nil,
      "N8: the Port menu's ⌘I on the picker hands the picker its own Identify")
check(onTheHub.setUpAction(forRowOf: "en5") == .setUpPort(portID: "en5")
      && overPicker.setUpAction(forRowOf: "en5") == nil,
      "S1: no set-up button is drawn anywhere while the assistant is up")

// MARK: S5 — one door for set-up.

let twoMacPorts = [
    snapshot(port("en5", "Back, far left", link: .macLinked, bridges: [bridge0]),
             configuration: .unconfigured(bridges: ["bridge0"])),
    snapshot(port("en6", "Back, left middle", link: .macLinked, bridges: [bridge0]),
             configuration: .unconfigured(bridges: ["bridge0"])),
]
let twoMacsHub = hubModel(twoMacPorts)
for action in [HubAction.setUpPort(portID: nil), .setUpPort(portID: "en5"), .setUpAgain(portID: "en6")] {
    twoMacsHub.perform(action)
    check(twoMacsHub.pendingSetUp == nil,
          "S5: with two Macs connected the one door refuses every set-up, whoever raised it: \(action.id)")
}
let tb4Hub = hubModel([farLeftPort], hardware: tb4)
tb4Hub.perform(.setUpPort(portID: nil))
tb4Hub.perform(.setUpAgain(portID: "en5"))
check(tb4Hub.pendingSetUp == nil && tb4Hub.setUpAction(forRowOf: "en5") == nil,
      "S5: on a Thunderbolt 4 Mac there is no set-up to open, and none to draw")
let doorHub = hubModel([farLeftPort, managed])
doorHub.perform(.setUpPort(portID: nil))
check(doorHub.pendingSetUp == .choose(suggested: nil), "N1: the footer and ⌘N open the picker")
let doorStage = StageModel()
if let chassis = ReceptacleCatalogue.chassis(for: .studioSix) { doorStage.picture = .chassis(chassis) }
doorStage.ports = [farLeftPort, managed].enumerated().map {
    StagePort(port: $1.port, physicalIndex: $0 + 1, configuration: cfg($1))
}
doorHub.attach(stage: doorStage)
doorStage.select("en5")
doorHub.pendingSetUp = nil
doorHub.perform(.setUpPort(portID: nil))
check(doorHub.pendingSetUp == .choose(suggested: "en5"), "N1: …offered the port selected on the hub")
doorHub.pendingSetUp = nil
doorHub.perform(.setUpPort(portID: "en5"))
check(doorHub.pendingSetUp == .port("en5"), "N2: a row's Set Up… names its port, so the run opens on Review")
doorHub.pendingSetUp = nil
doorHub.perform(.setUpAgain(portID: "en5"))
check(doorHub.pendingSetUp == .port("en5"), "N2: …and so does Set Up Again…")
let rowTerms = hubModel([returned, managed])
check(rowTerms.setUpAction(forRowOf: "en5") == .setUpAgain(portID: "en5")
      && rowTerms.setUpAction(forRowOf: "en6") == nil,
      "S5: the change log's and R30's set-up button is the port row's own, or none")
check(hubModel([staleNear]).setUpAction(forRowOf: "en5") == nil,
      "S5: a port set up by hand since its return is offered no set-up anywhere")
let returnEntry = ChangeEntry(
    port: "en5", positionName: "Back, far left", kind: .returned,
    sentence: ChangeSentence.returned(bridgeName: "Thunderbolt Bridge", removedService: true))
check(ChangeLogRows.rows(entries: [returnEntry], ports: [returned], noted: ["en5"]).first?.action
      == .setUpAgain(portID: "en5"),
      "S5: a returned entry offers the row's Set Up Again…")
check(ChangeLogRows.rows(entries: [returnEntry], ports: [staleNear], noted: ["en5"]).first?.action == nil,
      "S5: a returned entry whose port is now a near match shows no set-up button")
check(ChangeLogRows.rows(entries: [returnEntry], ports: [staleBare], noted: ["en5"]).first?.action
      == .setUpPort(portID: "en5"),
      "S5: …and one whose port was left bare since offers the row's own Set Up…")

// MARK: S2 — a write is never cut off.

final class ReplyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Bool] = []
    func add(_ reply: Bool) { lock.withLock { replies.append(reply) } }
    var all: [Bool] { lock.withLock { replies } }
}
let replies = ReplyLog()
let gate = BurstGate(reply: { replies.add($0) })
check(gate.terminateReply() == .terminateNow && replies.all.isEmpty,
      "S2: with no burst writing — the password dialog alone included — quitting goes ahead at once")
gate.begin()
check(gate.isRunning && gate.terminateReply() == .terminateLater && replies.all.isEmpty,
      "S2: while a burst writes, quitting waits, and nothing is answered yet")
gate.end()
check(!gate.isRunning && replies.all == [true], "S2: …and quits the moment the burst lands")
gate.begin()
gate.end()
check(replies.all == [true], "S2: a burst with no quit waiting on it answers nothing")
gate.begin()
gate.begin()
check(gate.terminateReply() == .terminateLater, "S2: two bursts at once: later")
gate.end()
check(replies.all == [true], "S2: …still later while one of them writes")
gate.end()
check(replies.all == [true, true], "S2: …and the quit goes ahead when the last one lands")
gate.end()
check(replies.all == [true, true] && !gate.isRunning, "an unmatched end neither answers nor counts below zero")
var restoreRun = OperationRun(steps: [.deleteCreatedService(named: "RDMA — Back, far left"), .checkBackInBridge])
check(restoreRun.isRunning && restoreRun.holdsTheWindow,
      "S2: from the password dialog on, before any step is reported, the window's close button is off")
restoreRun.mark(.deleteCreatedService(named: "RDMA — Back, far left"), .running)
check(restoreRun.holdsTheWindow, "S2: …and stays off while the checklist runs")
restoreRun.outcome = .succeeded(headline: nil, body: "Done.")
check(!restoreRun.holdsTheWindow, "S2: …and on again once it has landed")
check(!OperationRun(steps: []).holdsTheWindow, "S2: forgetting a note asks for no password and holds nothing")

// MARK: S3 — a refused S6 never re-plans over a kept note.

let agreement = KernelAgreement(
    agreed: true, settledOnItsOwn: true, retriedMembership: false, settledAfterRetry: false, reads: 1)
let partialExits = Exits()
let partial = makeFlow(
    ports: [farLeftPort, leftMiddle],
    planner: { ports in SetUpPorts(ports: ports).preview(world: quietWorld) },
    runner: { _ in
        AsyncThrowingStream { continuation in
            continuation.yield(.step(.saveUndoNote, .done))
            continuation.yield(.finished(SetUpPortsResult(
                ports: [SetUpPortResult(
                    bsdName: "en5", positionName: "Back, far left", serviceName: "RDMA — Back, far left",
                    createdServiceID: "NEW", leftBridges: ["Thunderbolt Bridge"], agreement: agreement)],
                unfinished: SetUpPortFailure(
                    bsdName: "en6", positionName: "Back, left middle",
                    refusal: Refusals.rolledBack(port: leftMiddle.observed, bridgeName: "Thunderbolt Bridge")),
                elapsed: 1.2)))
            continuation.finish()
        }
    },
    finish: { partialExits.leave() })
partial.open(.choose(suggested: nil))
partial.extendSelection("en5")
check(partial.selection == ["en5", "en6"], "a two-port run from the picker")
partial.goForward()
await settle { partial.reviewPlan != nil }
check(partial.reviewPlan?.ports.count == 2 && partial.primary?.isEnabled == true
      && partial.primary.map { text($0.title) } == "Set Up Two Ports",
      "…planned, and Set Up Two Ports is live, the count spelled out (L9)")
partial.goForward()
await settle { partial.apply?.phase == .refused }
check(partial.step == .apply && partial.applyRefusal?.code == "R10",
      "S3: the second port failed after the first landed: R10 on S6")
check(!partial.showsBack && partial.primary == nil, "S3: a refused S6 hides the footer's leading button")
check(partial.applyRefusal?.actions == [.tryAgain, .done, .copyDetails],
      "S3: R10's card holds every way out — Try Again · Done · Copy Details")
check(partial.applyRefusal?.rollbackLine == nil && partial.apply?.landedLines.map(text) == ["Back, far left is ready"],
      "§S6: after a partial run the card never says nothing has been changed — the port that landed is listed under it")
partial.goBack()
check(partial.step == .apply && partial.apply != nil && partialExits.count == 0,
      "S3: nothing behind the card re-plans — there is no Back on a refused S6")
partial.tryAgain()
check(partial.step == .review && partial.selection == ["en6"] && text(partial.stepCaption) == "Step 2 of 3",
      "S3: Try Again after a partial run plans only the port that did not land, in the same run")
let handExits = Exits()
let handRun = makeFlow(
    ports: [farLeftPort, leftMiddle],
    runner: { _ in
        AsyncThrowingStream { continuation in
            continuation.yield(.step(.saveUndoNote, .done))
            continuation.finish(throwing: Refusals.rollbackFailed(
                port: farLeftPort.observed, bridgeBSDName: "bridge0",
                bridgeDisplayName: "Thunderbolt Bridge", membersBefore: ["en5", "en6"], membersNow: ["en6"]))
        }
    },
    finish: { handExits.leave() })
handRun.open(.port("en5"))
await settle { handRun.reviewPlan != nil }
handRun.goForward()
await settle { handRun.apply?.phase == .refused }
check(handRun.step == .apply && handRun.applyRefusal?.code == "R11", "S3: the rollback itself failed: R11 on S6")
check(handRun.applyRefusal?.actions == [.openNetworkSettings, .copyDetails, .checkAgain, .done]
      && !handRun.showsBack,
      "S3: R11 — Open Network Settings · Copy Details · Check Again · Done, and no Back: it never returns to S5")
let handApply = handRun.apply
handRun.checkAgain()
check(handRun.step == .apply && handRun.applyRefusal?.code == "R11"
      && handApply != nil && handRun.apply === handApply && handExits.count == 0,
      "S3: R11's Check Again reads this Mac again in place — it never leaves S6 and never plans")
handRun.update(ports: [farLeftPort, leftMiddle], hardware: studio, switchState: .unobserved, findings: satisfied)
check(handRun.step == .apply && handRun.applyRefusal?.code == "R11",
      "S3: …and the re-read it asks for leaves the card where it is")
handRun.leave()
check(handExits.count == 1 && handRun.apply == nil, "S3: Done closes the assistant; the hub's needs-a-hand row takes over")
let expiredEarly = makeFlow(
    ports: [farLeftPort],
    runner: { _ in AsyncThrowingStream { $0.finish(throwing: Refusals.credentialExpired()) } })
expiredEarly.open(.port("en5"))
await settle { expiredEarly.reviewPlan != nil }
expiredEarly.goForward()
await settle { expiredEarly.apply == nil }
check(expiredEarly.step == .review && expiredEarly.reviewRefusal?.code == "R8"
      && expiredEarly.reviewRefusal?.actions == [.tryAgain, .copyDetails],
      "N5: R8 before the first write lands on S5, where the footer's Cancel is the way out and the card has no Done")

// MARK: S4 — needs-a-hand is its own row state.

let needsHand = snapshot(port("en6", "Back, left middle", link: .macLinked),
                         configuration: .unconfigured(bridges: []), baseline: ownNote)
check(needsHand.readiness == .needsAHand && !needsHand.readiness.isReady,
      "S4: a kept note over a port in no bridge with no service is needs-a-hand, not drift")
let handRow = PortRowPresentation(snapshot: needsHand)
check(handRow.symbol == "hand.raised" && handRow.symbolStyle == .attention
      && text(handRow.detail.state) == "Needs putting back by hand",
      "S4: hand.raised in orange, and Needs putting back by hand")
check(handRow.actions == [.restore(portID: "en6")] && !PortRowPresentation.offersSetUp(needsHand),
      "S4: its row offers Restore…, never a set-up")
check(picker(needsHand).isDimmed && picker(needsHand).actions == [.restore(portID: "en6")]
      && text(picker(needsHand).detail.state) == "Needs putting back by hand",
      "S4: on the picker it is dimmed like an already-ready row, and keeps Restore…")
check(ChoosePortReport.route(for: needsHand) == .needsAHand
      && ChoosePortReport(ports: [farLeftPort, needsHand], hardware: studio, selection: []).preSelection.isEmpty,
      "S4: never selectable and never pre-selected, though a Mac is on the end")
let handSituations = HubPresentation.situations(switchState: .unobserved, ports: [farLeftPort, needsHand])
check(handSituations.map(\.id) == ["needsAHand"] && handSituations.first?.actions == [.showMe(portID: "en6")],
      "S4: the hub says so once, with Show Me, and raises no drift row")
check(cfg(needsHand) == .drift, "§4.3: it wears drift's dashed ring")
let handFlow = makeFlow(ports: [farLeftPort, needsHand])
handFlow.open(.choose(suggested: "en6"))
check(handFlow.selection.isEmpty && !handFlow.pickedForTheUser,
      "S4: the footer never chooses it, from the hub or for the user")
handFlow.select("en6")
check(handFlow.selection.isEmpty && handFlow.presence == .picker(routed: "en6")
      && handFlow.routingLine.map(text) == "This one needs putting back by hand. Restore… puts it back.",
      "S4, N7: a click states the fact and names Restore…, which the Port menu then means")

// MARK: S6 — no dead Review for a near match.

let adoptingPlan: SetUpPortsPlan = {
    var plan = plannedFarLeft
    plan.ports[0].routesToAdopt = true
    return plan
}()
let backstop = makeFlow(ports: [farLeftPort], planner: { _ in adoptingPlan })
backstop.open(.port("en5"))
await settle { backstop.reviewPlan != nil }
check(backstop.reviewRefusal?.code == "R27" && backstop.reviewRefusal.map { text($0.headline) } == "This port is already set up"
      && backstop.reviewRefusal?.actions.isEmpty == true && backstop.reviewRefusal?.watchingLine == nil
      && backstop.primary == nil,
      "S6: a plan Core routes to Adopt reaches S5 as a card with no button, never an empty Review")
check(backstop.reviewRefusal.map { text($0.body) }
      == "This one was set up by hand, and properly. Adopt… looks after it without changing it.",
      "…in R27's words")

// RDMALink's own service, given a fixed IPv4 address since. On the picker a
// click routes to Restore… in R27's words, never R16's card; and should a
// Review reach it anyway, Core's R16 — which sees the address and not whose
// service it is — is drawn as R27's backstop, headed as R28 is.
let ownFixed = makeFlow(ports: [farLeftPort, driftedForeign])
ownFixed.open(.choose(suggested: nil))
ownFixed.select("en6")
check(ownFixed.selection.isEmpty && ownFixed.refusal == nil
      && ownFixed.routingLine.map(text) == "RDMALink set this one up, and it's been changed since. Restore… shows what changed.",
      "§S4: a click on RDMALink's own service with a fixed address names Restore…, and raises no R16")
let ownFixedPlan: SetUpPortsPlan = {
    var plan = SetUpPorts(ports: [OperationPort(driftedForeign.port)]).preview(world: quietWorld)
    plan.ports[0].refusal = Refusals.foreignService(driftedForeign.observed, reason: .staticIPv4Address)
    return plan
}()
let ownFixedReview = makeFlow(ports: [driftedForeign], planner: { _ in ownFixedPlan })
ownFixedReview.open(.port("en6"))
await settle { ownFixedReview.reviewPlan != nil }
check(ownFixedReview.reviewRefusal?.code == "R27"
      && ownFixedReview.reviewRefusal.map { text($0.headline) } == "This port's service isn't the one RDMALink made any more"
      && ownFixedReview.reviewRefusal.map { text($0.body) }
          == "RDMALink set this one up, and it's been changed since. Restore… shows what changed."
      && ownFixedReview.reviewRefusal?.actions.isEmpty == true && ownFixedReview.primary == nil,
      "§S5: Core's R16 over RDMALink's own service is R27's backstop, headed as R28 — never 'It isn't RDMALink's'")

// MARK: N4 — R16 and R17 on S5 keep the run's shape.

let foreignPlan: SetUpPortsPlan = {
    var plan = plannedFarLeft
    plan.ports[0].refusal = Refusals.foreignService(farLeftPort.observed, reason: .staticIPv4Address)
    return plan
}()
let namedR16 = makeFlow(ports: [farLeftPort], planner: { _ in foreignPlan })
namedR16.open(.port("en5"))
await settle { namedR16.reviewPlan != nil }
check(namedR16.reviewRefusal?.code == "R16"
      && namedR16.reviewRefusal?.actions == [.openNetworkSettings, .copyDetails]
      && text(namedR16.backTitle) == "Cancel",
      "N4: R16 in a run that opened on S5 — Open Network Settings · Copy Details, and the footer's Cancel")
let pickerR16Exits = Exits()
let pickerR16 = makeFlow(ports: [farLeftPort], planner: { _ in foreignPlan }, finish: { pickerR16Exits.leave() })
pickerR16.open(.choose(suggested: "en5"))
pickerR16.goForward()
await settle { pickerR16.reviewPlan != nil }
check(pickerR16.reviewRefusal?.actions == [.openNetworkSettings, .chooseAnotherPort, .copyDetails],
      "N4: in a run that opened on the picker it keeps Choose Another Port")
pickerR16.chooseAnotherPort()
check(pickerR16.step == .choose && pickerR16Exits.count == 0 && text(pickerR16.stepCaption) == "Step 1 of 3",
      "N4: …which is Back to the picker, the count unchanged")
let farLeftArrived = snapshot(port("en5", "Back, far left", link: .device, bridges: [bridge0]),
                              configuration: .unconfigured(bridges: ["bridge0"]))
for (lookAgain, caption) in [(makeFlow(ports: [farLeftPort, leftMiddle]), "Step 1 of 2"),
                             (makeFlow(ports: [farLeftPort, leftMiddle]), "Step 2 of 3")] {
    if caption == "Step 1 of 2" {
        lookAgain.open(.port("en5"))
    } else {
        lookAgain.open(.choose(suggested: "en5"))
        lookAgain.goForward()
    }
    await settle { lookAgain.reviewPlan != nil }
    lookAgain.update(ports: [farLeftArrived, leftMiddle], hardware: studio, switchState: .unobserved,
                     findings: satisfied)
    check(lookAgain.reviewRefusal?.code == "R17" && lookAgain.attentionPortIDs.contains("en5"),
          "R17: a cable moved while S5 was up — the card, and the port rings (\(caption))")
    lookAgain.takeAnotherLook()
    check(lookAgain.step == .review && lookAgain.refusal == nil && text(lookAgain.stepCaption) == caption
          && lookAgain.breathing == ["en5"] && lookAgain.attentionPortIDs.contains("en5"),
          "N4: Take Another Look reads S5 again in place, the count unchanged, the port breathing once (\(caption))")
    await settle { lookAgain.reviewPlan != nil }
    check(lookAgain.reviewRefusal == nil && lookAgain.primary?.isEnabled == true,
          "…and what is true now is the screen again (\(caption))")
}

// MARK: N5 — a card in the working area never repeats the footer's way out.

for card in [WizardRefusals.notAnAdministrator, WizardRefusals.noAuthorization,
             WizardRefusals.networkLockHeld(bySystemSettings: true),
             WizardRefusals.networkLockHeld(bySystemSettings: false), WizardRefusals.managedByProfile,
             WizardRefusals.usbPort(isMacMini: false),
             WizardRefusals.foreignService(positionName: "Back, far left", portBSDName: "en5"),
             WizardRefusals.arrangementChanged(), WizardRefusals.credentialExpired, WizardRefusals.rolledBack] {
    check(!card.actions.contains(.back) && !card.actions.contains(.cancel),
          "N5: no Back or Cancel on a card: \(card.code)")
}
for code in RefusalCode.allCases {
    let card = WizardRefusal(Refusal(code: code, headline: "", body: ""))
    check(!card.actions.contains(.back) && !card.actions.contains(.cancel),
          "N5: no Back or Cancel on Core's \(code.rawValue)")
}
if let r31Refusal = Refusals.macRecognized(unrecognized) {
    let r31Card = WizardRefusal(r31Refusal)
    check(r31Card.actions.isEmpty && r31Card.watchingLine == nil,
          "N5: R31's fallback has no buttons and never says it is watching — it never clears")
} else {
    check(false, "the unrecognized fixture raises R31")
}

// MARK: N6 — Escape on the picker puts a card away first.

let escapeExits = Exits()
let escapeFlow = makeFlow(ports: [farLeftPort, leftMiddle, usbOnly], finish: { escapeExits.leave() })
escapeFlow.open(.choose(suggested: nil))
escapeFlow.select(usbOnly.id)
check(escapeFlow.refusal?.code == "R3" && escapeFlow.escapePutsCardAway && escapeFlow.selection == ["en6"],
      "a USB-only row clicked on the picker: R3's card over RDMALink's pick")
escapeFlow.escape()
check(escapeFlow.refusal == nil && escapeFlow.selection == ["en6"] && escapeFlow.step == .choose
      && escapeExits.count == 0,
      "N6: Escape puts the card away first, the selection as it was")
escapeFlow.escape()
check(escapeExits.count == 1, "N6: …and the next Escape is Cancel")
let clickExits = Exits()
let clickFlow = makeFlow(ports: [farLeftPort, usbOnly], finish: { clickExits.leave() })
clickFlow.open(.choose(suggested: "en5"))
clickFlow.select(usbOnly.id)
clickFlow.goBack()
check(clickExits.count == 1, "N6: a click on Cancel with a card up is still Cancel")

// MARK: N7, N8.

check(ChoosePortReport.routingLine(for: .adopt, snapshot: outside).map(text)
      == "This one was set up by hand, and properly. Adopt… looks after it without changing it."
      && ChoosePortReport.routingLine(for: .adopt, snapshot: staleNear).map(text)
      == "This one was set up by hand, but not quite the way a link needs. Adopt… shows what to change."
      && ChoosePortReport.routingLine(for: .editedService, snapshot: driftedNear).map(text)
      == "RDMALink set this one up, and it's been changed since. Restore… shows what changed.",
      "N7: R27's lines state facts and name the row's own button")
let frozenIdentify = makeFlow(ports: [farLeftPort])
frozenIdentify.open(.port("en5"))
frozenIdentify.beginIdentify()
check(frozenIdentify.identify == nil && frozenIdentify.presence == .underWay,
      "N8: Identify is the picker's alone — nothing starts it on Review")

// MARK: Group 3 — labels.

// L1: an ellipsis means there is more to do before the command is done. A
// title that opens somewhere the user still decides — a sheet, the set-up
// assistant, Identify's watch — ends in …; one finished on the click carries
// none (§1.3 rule 11). The switch is exhaustive, so a new action has to be
// sorted before this compiles.
func opensSomewhere(_ action: HubAction) -> Bool {
    switch action {
    case .setUpPort, .setUpAgain, .identifyPort, .adopt, .restore, .returnToBridge,
         .stopManaging, .restoreAll:
        true
    case .showMe, .changeLog, .forgetThisNote:
        false
    }
}
for action in [HubAction.setUpPort(portID: nil), .setUpPort(portID: "en3"), .setUpAgain(portID: "en5"),
               .identifyPort(portID: nil), .adopt(portID: "en2"), .restore(portID: "en6"),
               .returnToBridge(portID: "en2"), .stopManaging(portID: "en7"), .restoreAll,
               .showMe(portID: "en6"), .changeLog, .forgetThisNote(port: "en9")] {
    check(text(action.title).hasSuffix("…") == opensSomewhere(action)
          && text(action.rowTitle).hasSuffix("…") == opensSomewhere(action),
          "L1: the hub's \(text(action.title)) carries an ellipsis exactly when it opens somewhere")
}
for action in WizardAction.allCases {
    let opens = action == .identifyPort || action == .identifyAgain
    check(text(action.title).hasSuffix("…") == opens,
          "L1: the assistant's \(text(action.title)) — only Identify's watch earns an ellipsis")
}
for action in RestoreAction.allCases {
    let opens = action == .stopManaging || action == .setUpAgain
    check(text(action.title).hasSuffix("…") == opens,
          "L1: the sheet's \(text(action.title)) — the openers have it, the committers don't")
}
check(!plannedFarLeft.buttonTitle.hasSuffix("…"),
      "L1: Review's Set Up Port raises only macOS's password dialog, which doesn't count")

// L5: Stop Managing… is the one command for forgetting the note of a port
// still on this Mac — drift proper included — and never for a ready port
// RDMALink set up, or one that needs a hand.
check(hubModel([drifted]).canPerform(.stopManaging(portID: "en6")),
      "L5: a drifted port's note can be forgotten, through the stop-managing sheet")
check(hubModel([adopted]).canPerform(.stopManaging(portID: "en7"))
      && hubModel([returned]).canPerform(.stopManaging(portID: "en5")),
      "L5: …as an adopted port's and a return record's always could")
check(!hubModel([managed]).canPerform(.stopManaging(portID: "en6")),
      "L5: never a ready port RDMALink set up — its way back is Restore…")
check(!hubModel([needsHand]).canPerform(.stopManaging(portID: "en6")),
      "L5: never a port that needs a hand — its note is the only record of where it came from")
let forgetHub = hubModel([drifted])
forgetHub.perform(.stopManaging(portID: "en6"))
check(forgetHub.sheet == .restore(.stopManaging(portID: "en6")),
      "L5: the drift row's Stop Managing… opens S10's stop-managing form, never forgets on the click")

// L9: counts are words, from one formatter, in a button or a counter as in a
// sentence; and with more than one port chosen each informational line names
// its port.
let dockPort = snapshot(port("en8", "Back, far right", link: .device, bridges: [bridge0]),
                        configuration: .unconfigured(bridges: ["bridge0"]))
let twoChosen = ChoosePortReport(ports: [farLeftPort, leftMiddle, dockPort], hardware: studio,
                                 selection: ["en5", "en8"])
check(twoChosen.counter.map(text) == "Two ports selected"
      && twoChosen.multiSelectNote.map(text) == "RDMALink will prepare both, one after the other, from the same password.",
      "L9: Two ports selected, and both")
check(twoChosen.informationalLines.map { text($0.text) } == [
        "Nothing is plugged into Back, far left yet. That's fine — the address appears when a Mac arrives.",
        "There's a dock or a display in Back, far right. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.",
      ],
      "L9: with two ports chosen each informational line names its port")
let threeChosen = ChoosePortReport(ports: [farLeftPort, leftMiddle, dockPort], hardware: studio,
                                   selection: ["en5", "en6", "en8"])
check(threeChosen.counter.map(text) == "Three ports selected"
      && threeChosen.multiSelectNote.map(text)
      == "RDMALink will prepare all three, one after the other, from the same password.",
      "L9: Three ports selected, and all three — never both")
let oneChosen = ChoosePortReport(ports: [farLeftPort, dockPort], hardware: studio, selection: ["en8"])
check(oneChosen.counter == nil && oneChosen.multiSelectNote == nil
      && oneChosen.informationalLines.map { text($0.text) } == [
        "There's a dock or a display in this port. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.",
      ],
      "L9: one port chosen keeps \"this port\", with no counter and no note")
let threePortPlan = SetUpPorts(ports: [farLeftPort, leftMiddle, dockPort].map { OperationPort($0.port) })
    .preview(world: quietWorld)
check(threePortPlan.buttonTitle == "Set Up Three Ports"
      && text(ApplyRun(plan: threePortPlan, runner: { _ in AsyncThrowingStream { $0.finish() } })
        .runningHeadline) == "Setting up three ports",
      "L9: the button and the headline S6 draws after it name one count one way")
check(ThisMacPresentation.spelledOut(3, capitalized: false) == Counts.spelledOut(3, capitalized: false)
      && ThisMacPresentation.spelledOut(7) == "Seven",
      "L9: the app's counts are Core's one formatter")
let watching = IdentifySession()
watching.observe((1...5).map {
    IdentifyObservation(id: "en\($0)", positionName: "Port \($0)", isThunderbolt: true, isOccupied: false)
})
check(watching.statusLine.map(text) == "Watching all five ports…",
      "L9: Identify's status line spells every count out, not only six, four and three")

// L8: Review's disclosure is a label, so it is sentence case.
check(SetUpPortsPlan.whatRDMALinkWontTouchLabel == "What RDMALink won't touch",
      "L8: What RDMALink won't touch, in sentence case")

// L12: the Port menu's Restore… means one port or is unavailable; the
// footer's falls back to Restore All Ports, which nothing beside it offers.
let twoNotes = hubModel([managed, adopted])
check(twoNotes.restoreOnePort == nil && twoNotes.restoreAction == .restoreAll,
      "L12: two notes and none in hand — the menu's Restore… means nothing, the footer's is Restore All")
check(hubModel([managed]).restoreOnePort == .restore(portID: "en6")
      && hubModel([managed]).restoreAction == .restore(portID: "en6"),
      "L12: the only noted port is the one both Restore…s mean")

// MARK: Group 4 — screen structure and copy.

// T2: a screen's own buttons live in band 4. S4b's answer brings its other
// buttons into the footer, just before its default; S7's footer is `What to
// Do on the Other Mac` · `Done`; no other screen adds any.
let identifying = makeFlow(ports: [farLeftPort, leftMiddle])
identifying.open(.choose(suggested: nil))
identifying.beginIdentify()
check(identifying.footerSecondaries.isEmpty && identifying.primary == nil && identifying.showsBack,
      "T2: S4b watching — Cancel alone in the footer")
let unpluggedMiddle = snapshot(port("en6", "Back, left middle", link: .empty, bridges: [bridge0]),
                               configuration: .unconfigured(bridges: ["bridge0"]))
identifying.update(ports: [farLeftPort, unpluggedMiddle], hardware: studio, switchState: .unobserved,
                   findings: satisfied)
check(identifying.footerSecondaries == [.identifyAgain, .chooseFromList]
      && identifying.primary.map { text($0.title) } == "Use This Port",
      "T2: S4b's answer — Identify Again… and Choose from List just before Use This Port, all in the footer")
let readyRun = makeFlow(ports: [farLeftPort, leftMiddle])
readyRun.open(.port("en5"))
check(readyRun.footerSecondaries.isEmpty, "T2: Review adds no button beside its own")
readyRun.route(to: .ready, openedOn: .review)
check(readyRun.footerSecondaries == [.whatToDoOnTheOtherMac]
      && readyRun.primary.map { text($0.title) } == "Done" && !readyRun.showsBack,
      "T2: S7's footer is What to Do on the Other Mac · Done")
check(text(WizardAction.whatToDoOnTheOtherMac.title) == "What to Do on the Other Mac",
      "T2: S7's button keeps §S7's words — no ellipsis, it shows and asks nothing")

// T4: orange asks for an act. What is plugged in only informs, and each fact
// has one sentence, the picker's and Review's alike.
let planPort = plannedFarLeft.ports[0]
check(planPort.warnings == [
        "RDMA over Thunderbolt is still off. The port will be ready; RDMA will start using it after you turn that on and restart.",
      ] && planPort.informationalLines == [
        "Nothing is plugged into this port yet. That's fine — the address appears when a Mac arrives.",
      ],
      "T4: Review's RDMA-off line is a warning; nothing plugged in is an informational line")
check(ChooseInformationalLine(farLeftPort).map { text($0.text) } == planPort.informationalLines.first,
      "T4: the picker and Review say the same sentence for the same fact")

// T5: R23's and R31's read-only hubs state the switch and offer no button.
check(ThisMacPresentation.rdmaRow(.off, isReadOnly: true)
        == ThisMacRowModel(id: "rdma", text: "RDMA over Thunderbolt — Off"),
      "T5: read-only hubs — RDMA over Thunderbolt — Off, with no Turn It On…")
check(ThisMacPresentation.rdmaRow(.off)?.action == .turnItOn
      && ThisMacPresentation.rdmaRow(.off).map { text($0.text) } == "RDMA over Thunderbolt — Off. Turn it on to finish.",
      "T5: …while a Mac RDMALink sets up keeps Turn it on to finish")
check(HubPresentation.footer(hardware: unrecognized, ports: []).primary == nil
      && HubPresentation.footer(hardware: tb4, ports: []).primary == nil,
      "T5: read-only is the hub that offers no set-up, R23 and R31 alike")

// T6: the hub body names every ready port and says which are linked, and
// "Nothing else on this Mac was changed" only while it is true.
// (`linkedManaged` is §S8's fixture above: Back, left middle, ready and linked.)
check(text(HubPresentation.copy(hardware: studio, ports: [managed]).body)
      == "Back, left middle is set up and waiting for a Mac. Nothing else on this Mac was changed.",
      "T6: one port, waiting")
check(text(HubPresentation.copy(hardware: studio, ports: [linkedManaged]).body)
      == "Back, left middle is set up and linked. Nothing else on this Mac was changed.",
      "T6: one port, linked")
check(text(HubPresentation.copy(hardware: studio, ports: [managed, adopted]).body)
      == "Back, left middle and Back, right middle are set up and waiting for a Mac. Nothing else on this Mac was changed.",
      "T6: two ports named, the headline's two")
check(text(HubPresentation.copy(hardware: studio, ports: [linkedManaged, adopted]).body)
      == "Back, left middle is set up and linked, and Back, right middle is set up and waiting for a Mac. Nothing else on this Mac was changed.",
      "T6: which are linked and which are waiting")
let linkedAdopted = snapshot(port("en7", "Back, right middle", link: .macLinked),
                             configuration: .readyForRDMA(serviceID: "THEIRS"), baseline: adoptedNote)
let thirdReady = snapshot(port("en8", "Back, far right"), configuration: .readyForRDMA(serviceID: "THIRD"),
                          baseline: PortBaseline(
                            bsdName: "en8", receptacle: 3, positionName: "Back, far right",
                            bridges: [BridgeMembership(bridgeName: "bridge0", members: ["en8"], isActive: true)],
                            createdService: CreatedServiceRecord(identifier: "THIRD", interfaceBSDName: "en8")))
check(thirdReady.readiness == .managed, "T6: the third fixture is ready")
check(text(HubPresentation.copy(hardware: studio, ports: [linkedManaged, linkedAdopted, thirdReady]).body)
      == "Back, left middle and Back, right middle are set up and linked, and Back, far right is set up and waiting for a Mac. Nothing else on this Mac was changed.",
      "T6: three ports, plural where a half names more than one")
check(text(HubPresentation.copy(hardware: studio, ports: [managed, returned]).body)
      == "Back, left middle is set up and waiting for a Mac.",
      "T6: a return record says RDMALink changed something else, so the sentence goes")
let driftedElsewhere = snapshot(
    port("en9", "Back, far right", bridges: [bridge0]), configuration: .unconfigured(bridges: ["bridge0"]),
    baseline: PortBaseline(
        bsdName: "en9", receptacle: 3, positionName: "Back, far right",
        bridges: [BridgeMembership(bridgeName: "bridge0", members: ["en9"], isActive: true)],
        createdService: CreatedServiceRecord(identifier: "GONE", interfaceBSDName: "en9")))
check(driftedElsewhere.readiness == .drifted, "T6: the fixture has drifted")
check(text(HubPresentation.copy(hardware: studio, ports: [linkedManaged, driftedElsewhere]).body)
      == "Back, left middle is set up and linked.",
      "T6: so does a drifted port's note")

// T7: S6's checklist is S5's rows, and "Thunderbolt Bridge" is a name.
let farLeftRun = ApplyRun(plan: plannedFarLeft, runner: { _ in AsyncThrowingStream { $0.finish() } })
let reviewTitles = planPort.rows.map(\.title)
check(reviewTitles == ["Save how to undo this", "Leave Thunderbolt Bridge",
                       "Get its own network service", "Turn IPv4 off, IPv6 to link-local"],
      "T7: Review's four titles, no article before Thunderbolt Bridge")
check(farLeftRun.rows.map(\.text).filter(reviewTitles.contains)
      == reviewTitles.filter { $0 != "Leave Thunderbolt Bridge" },
      "T7: every pending S6 row a port in no bridge runs is one of Review's titles, word for word")
// (`addressed` is §S8's fixture above: ready, linked, with its address.)
check(text(ReadyReport(ports: [addressed], switchState: .on).body)
      == "The port has left Thunderbolt Bridge and has its own link-local address. It'll carry RDMA as soon as the other Mac is set up the same way.",
      "T7: S7's body has no article before Thunderbolt Bridge")

// T8: the change log's body line, or the empty sentence in its place.
check(text(ChangeLogRows.body(isEmpty: false))
      == "RDMALink keeps one small note per port, in your Library folder. They're only notes — they don't change anything on their own."
      && text(ChangeLogRows.body(isEmpty: true))
      == "Nothing yet. When RDMALink changes something, it'll be listed here with a way back.",
      "T8: S11's body is where the notes live; with no entries the empty sentence takes its place")

// T9: the voice leftovers — RDMALink is the subject whenever someone acts.
check(text(WizardRefusals.managedByProfile.body).contains(
        "Better to say so now than have you wonder later why the link keeps vanishing."),
      "T9: R13")
check(text(WizardRefusals.unreadableBridge(positionName: "Back, far left", portBSDName: "en5").body)
        .hasSuffix("RDMALink won't guess at this. Have a look in Network settings, under Manage Virtual Interfaces, and RDMALink checks again when you're back."),
      "T9: R15")
check(text(WizardRefusals.everyPortOccupied(detail: nil).body)
      == "You can still prepare any of them — or free up the one you want for the link.",
      "T9: R26")
let nearMatch = snapshot(port("en2", "Back, far right"),
                         configuration: .nearMatch(serviceID: "HAND", differences: [.ipv6NotLinkLocal(method: "Automatic")]))
check(AdoptForm(nearMatch).map { text($0.body(nearMatch)) }?
        .hasSuffix("but here's exactly what to change, and RDMALink adopts the port the moment it matches.") == true,
      "T9: S9's near match")

// T10, T11: the Restore sheet's questions name no port — the body does — and
// the sheet shows its question over the spinner while it reads this Mac.
check(RestoreSheetHeadline.whileReading(.restore(portID: "en6"), note: ownNote)
        == "Put this port back the way it was?"
      && RestoreSheetHeadline.whileReading(.restore(portID: "en7"), note: adoptedNote)
        == "Return this port to Thunderbolt Bridge?"
      && RestoreSheetHeadline.whileReading(.returnToBridge(portID: "en2"), note: nil)
        == "Return this port to Thunderbolt Bridge?"
      && RestoreSheetHeadline.whileReading(.stopManaging(portID: "en7"), note: adoptedNote)
        == "Stop managing this port?"
      && RestoreSheetHeadline.whileReading(.all, note: nil) == "Put every port back?",
      "T10/T11: the question the plan will ask, known before the plan is read, with no position name at its head")
check(RestorePort.runningHeadline == "Putting this port back"
      && ReturnToBridge.runningHeadline() == "Returning this port to Thunderbolt Bridge"
      && StopManaging.runningHeadline == "Forgetting this port's note"
      && RestoreAll.runningHeadline == "Putting every port back",
      "T10: while the checklist runs the headline says what is happening")

// MARK: Review pass — a sheet is never replaced from outside it (§2.6).

let sheetOverPicker = hubModel([farLeftPort, managed, outside, adopted])
sheetOverPicker.assistant = .picker(routed: "en6")
check(sheetOverPicker.canPerform(.restore(portID: "en6")) && sheetOverPicker.canPerform(.identifyPort(portID: nil)),
      "§2.7: over the picker, the routed row's Restore… and Identify Port… are live")
sheetOverPicker.sheet = .restore(.restore(portID: "en6"))
check(!sheetOverPicker.canPerform(.identifyPort(portID: nil))
      && !sheetOverPicker.canPerform(.restore(portID: "en6"))
      && !sheetOverPicker.canPerform(sheetOverPicker.restoreAction),
      "§2.6: with the row's sheet up, neither is — S4b never starts under a sheet, and the sheet is never replaced")
let sheetOnHub = hubModel([farLeftPort, managed, outside, adopted])
sheetOnHub.sheet = .restore(.restore(portID: "en6"))
sheetOnHub.start(steps: [.checkBackInBridge]) { _ in
    try await Task.sleep(for: .seconds(30))
    return .failed(details: "")
}
check(sheetOnHub.run?.isRunning == true, "a Restore sheet's checklist is running")
for refused in [HubAction.restoreAll, .setUpPort(portID: nil), .setUpPort(portID: "en5"), .changeLog,
                .restore(portID: "en6"), .identifyPort(portID: nil), .adopt(portID: "en2"),
                .stopManaging(portID: "en7")] {
    check(!sheetOnHub.canPerform(refused), "§2.6: on the hub too, nothing in the menus while a sheet is up: \(refused.id)")
}
let runningRun = sheetOnHub.run
sheetOnHub.perform(.restoreAll)
sheetOnHub.perform(.restore(portID: "en6"))
sheetOnHub.perform(.setUpPort(portID: nil))
check(sheetOnHub.run == runningRun && sheetOnHub.sheet == .restore(.restore(portID: "en6"))
      && sheetOnHub.pendingSetUp == nil,
      "§S10: a running checklist is never replaced, and no second run starts beside it")

// MARK: Review pass — no card over macOS's password dialog.

let dialogUp = makeFlow(
    ports: [farLeftPort, leftMiddle],
    runner: { _ in
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: .seconds(30))
                continuation.finish()
            }
        }
    })
dialogUp.open(.port("en5"))
await settle { dialogUp.reviewPlan != nil }
dialogUp.goForward()
check(dialogUp.isAuthorizing && !dialogUp.showsBack, "the password dialog is up, and S5's footer has no way back")
dialogUp.update(ports: [farLeftArrived, leftMiddle], hardware: studio, switchState: .unobserved, findings: satisfied)
check(dialogUp.refusal == nil && dialogUp.reviewRefusal == nil && dialogUp.apply != nil,
      "§S5: a cable that moves while the dialog is up raises no card — Core re-reads inside the burst and answers R17 itself")
dialogUp.takeAnotherLook()
dialogUp.goBack()
check(dialogUp.apply != nil && dialogUp.isAuthorizing,
      "…and nothing lets go of a run that is waiting on the dialog, which would then write with nothing on screen")

// MARK: Review pass — Check Again on a card the run put up.

let busyEarly = makeFlow(
    ports: [farLeftPort],
    runner: { _ in
        AsyncThrowingStream { $0.finish(throwing: NetworkConfigurationError.busy(step: "lock", code: 3005)) }
    })
busyEarly.open(.port("en5"))
await settle { busyEarly.reviewPlan != nil }
busyEarly.goForward()
await settle { busyEarly.apply == nil }
check(busyEarly.step == .review && busyEarly.reviewRefusal?.code == "R12"
      && busyEarly.reviewRefusal?.actions == [.checkAgain] && busyEarly.primary == nil,
      "R12 before the first write lands on S5, with Check Again its one button")
busyEarly.checkAgain()
check(busyEarly.refusal == nil && busyEarly.step == .review, "§6.2 R12: Check Again puts the card away and reads S5 again")
await settle { busyEarly.reviewPlan != nil }
check(busyEarly.reviewRefusal == nil && busyEarly.primary?.isEnabled == true,
      "…so Set Up Port can ask again")
let stuckExits = Exits()
let stuck = makeFlow(
    ports: [farLeftPort],
    runner: { _ in
        AsyncThrowingStream { continuation in
            continuation.yield(.step(.saveUndoNote, .done))
            continuation.finish(throwing: Refusal(
                code: .portStillInBridge, headline: "macOS wouldn't let go of that port",
                body: "RDMALink couldn't remove Back, far left from Thunderbolt Bridge.", subjects: ["en5"]))
        }
    },
    finish: { stuckExits.leave() })
stuck.open(.port("en5"))
await settle { stuck.reviewPlan != nil }
stuck.goForward()
await settle { stuck.apply?.phase == .refused }
check(stuck.step == .apply && stuck.applyRefusal?.code == "R9"
      && stuck.applyRefusal?.actions == [.openNetworkSettings, .checkAgain, .copyDetails, .done],
      "R9 on S6: its own row, and Done")
stuck.checkAgain()
check(stuck.step == .review && stuck.apply == nil && stuck.selection == ["en5"] && stuckExits.count == 0
      && text(stuck.stepCaption) == "Step 1 of 2",
      "§S6: R9's Check Again goes back to S5 the way Try Again does — nothing was written for the port")

// MARK: Review pass — a partial run that ran out of time.

let expiredPartial = makeFlow(
    ports: [farLeftPort, leftMiddle],
    planner: { ports in SetUpPorts(ports: ports).preview(world: quietWorld) },
    runner: { _ in
        AsyncThrowingStream { continuation in
            continuation.yield(.step(.saveUndoNote, .done))
            continuation.yield(.finished(SetUpPortsResult(
                ports: [SetUpPortResult(
                    bsdName: "en5", positionName: "Back, far left", serviceName: "RDMA — Back, far left",
                    createdServiceID: "NEW", leftBridges: ["Thunderbolt Bridge"], agreement: agreement)],
                unfinished: SetUpPortFailure(
                    bsdName: "en6", positionName: "Back, left middle",
                    refusal: Refusals.credentialExpired(port: leftMiddle.observed)),
                elapsed: 1.2)))
            continuation.finish()
        }
    })
expiredPartial.open(.choose(suggested: nil))
expiredPartial.extendSelection("en5")
expiredPartial.goForward()
await settle { expiredPartial.reviewPlan != nil }
expiredPartial.goForward()
await settle { expiredPartial.apply?.phase == .refused }
check(expiredPartial.applyRefusal?.code == "R8" && expiredPartial.applyRefusal?.rollbackLine == nil,
      "§6.2 R8: after a port landed, the card leaves off \"Nothing has been changed.\"")
check(WizardRefusal(Refusals.credentialExpired()).rollbackLine.map(text) == "Nothing has been changed.",
      "…which it keeps when nothing landed")

// MARK: Review pass — a service of its own on a port still in a bridge.

let inBridgeNear = snapshot(
    port("en2", "Back, far right", bridges: [bridge0]),
    configuration: .nearMatch(serviceID: "HAND", differences: [.stillInBridge("bridge0"), .ipv4NotOff(method: "DHCP")]))
let inBridgeMatch = snapshot(
    port("en2", "Back, far right", bridges: [bridge0]),
    configuration: .nearMatch(serviceID: "HAND", differences: [.stillInBridge("bridge0")]))
for inBridge in [inBridgeNear, inBridgeMatch] {
    check(inBridge.readiness == .plain && inBridge.hasAServiceInABridge && AdoptForm(inBridge) == nil
          && ChoosePortReport.route(for: inBridge) == .foreignService,
          "§S9, R16: a service of its own on a port still in a bridge is no near match Adopt can take")
    let hub = hubModel([farLeftPort, inBridge])
    let row = PortRowPresentation(snapshot: inBridge)
    check(row.actions.isEmpty && row.actions.allSatisfy(hub.canPerform),
          "§S1: its row offers no button that couldn't act — no Adopt…, no Set Up…")
    check(picker(inBridge).isDimmed && picker(inBridge).actions.isEmpty,
          "§S4: on the picker it is dimmed and names no route")
}
let inBridgeFlow = makeFlow(ports: [farLeftPort, inBridgeNear])
inBridgeFlow.open(.choose(suggested: nil))
inBridgeFlow.select("en2")
check(inBridgeFlow.refusal?.code == "R16" && inBridgeFlow.selection.isEmpty && inBridgeFlow.routingLine == nil
      && inBridgeFlow.refusal.map { text($0.body) }
        == "There's a service of its own on Back, far right, and the port is still in a bridge. It isn't RDMALink's and it isn't what a link needs, and RDMALink won't quietly rewrite something you or someone else set up on purpose. Remove it in Network settings if it's stale, or choose another port.",
      "§6.2 R16: a click raises R16's card in its second body")
let driftedInBridge = snapshot(
    port("en6", "Back, left middle", bridges: [bridge0]),
    configuration: .nearMatch(serviceID: "HAND", differences: [.stillInBridge("bridge0")]), baseline: ownNote)
check(driftedInBridge.readiness == .drifted && PortRowPresentation(snapshot: driftedInBridge).actions.isEmpty
      && Situation.drift(driftedInBridge).actions == [.stopManaging(portID: "en6")],
      "§S1: drifted onto a hand-made service in a bridge — no Set Up Again…, no Adopt…; the drift row keeps Stop Managing…")
let inBridgeFarLeft = snapshot(
    port("en5", "Back, far left", bridges: [bridge0]),
    configuration: .nearMatch(serviceID: "HAND", differences: [.stillInBridge("bridge0")]))
let inBridgeBackstop = makeFlow(ports: [inBridgeFarLeft], planner: { _ in adoptingPlan })
inBridgeBackstop.open(.port("en5"))
await settle { inBridgeBackstop.reviewPlan != nil }
check(inBridgeBackstop.reviewRefusal?.code == "R16"
      && inBridgeBackstop.reviewRefusal?.actions == [.openNetworkSettings, .copyDetails],
      "§S5: the same port reaching Review is R16's card there too, never an empty Review")

// MARK: Review pass — R27's backstop is headed as its route is.

let nearFarLeft = snapshot(
    port("en5", "Back, far left"),
    configuration: .nearMatch(serviceID: "HAND", differences: [.ipv6NotLinkLocal(method: "Automatic")]))
let nearBackstop = makeFlow(ports: [nearFarLeft], planner: { _ in adoptingPlan })
nearBackstop.open(.port("en5"))
await settle { nearBackstop.reviewPlan != nil }
check(nearBackstop.reviewRefusal?.code == "R27"
      && nearBackstop.reviewRefusal.map { text($0.headline) } == "Nearly a match"
      && nearBackstop.reviewRefusal.map { text($0.body) }
        == "This one was set up by hand, but not quite the way a link needs. Adopt… shows what to change.",
      "§S5: a near match's backstop carries S9's near-match headline")
check(text(ChoosePortReport.backstopHeadline(for: .editedService, snapshot: driftedNear))
        == "This port's service isn't the one RDMALink made any more"
      && text(ChoosePortReport.backstopHeadline(for: .adopt, snapshot: outside)) == "This port is already set up"
      && text(ChoosePortReport.backstopHeadline(for: .alreadyReady, snapshot: managed)) == "This port is already set up",
      "§6.2 R27: R28's headline for RDMALink's own service edited since, S9's full match otherwise")

// MARK: Review pass — an adopted port that is already ready.

check(ChoosePortReport.routingLine(for: .alreadyReady, snapshot: adopted).map(text)
        == "This one's already a link, looked after by RDMALink. Return to Bridge… puts it in Thunderbolt Bridge."
      && ChoosePortReport.routingLine(for: .alreadyReady, snapshot: managed).map(text)
        == "This one's already a link. Restore… puts it back.",
      "§6.2 R27: an adopted port's line names Return to Bridge…, the sheet its row opens")
let adoptedOverPicker = hubModel([farLeftPort, adopted])
adoptedOverPicker.assistant = .picker(routed: "en7")
check(adoptedOverPicker.menuPortID == "en7" && adoptedOverPicker.canPerform(.returnToBridge(portID: "en7"))
      && adoptedOverPicker.restoreOnePort.map(adoptedOverPicker.canPerform) == false,
      "§2.7: the Port menu's Return to Bridge… means that row, and its Restore… is unavailable")

// MARK: Review pass — R20 in the assistant, R28 over the picker, the Checked count.

let r20Card = WizardRefusal(Refusals.notBackInBridge(
    port: farLeftPort.observed, bridgeName: "Thunderbolt Bridge", removedService: true))
check(r20Card.actions == [.openNetworkSettings, .copyDetails] && r20Card.isAttention && r20Card.detail == nil
      && r20Card.watchingLine == nil,
      "§6.2 R20 on S5: Open Network Settings · Copy Details, the orange symbol, and no Steps paragraph naming Try Again")
let r28 = Refusals.createdServiceEdited(port: farLeftPort.observed, differences: ["IPv4 is set to Manual now"])
check(r28.body.hasSuffix("Remove it yourself in Network settings if you're done with it, or Stop Managing leaves everything exactly where it is."),
      "§6.2 R28 names Stop Managing where its row has it")
check(RestoreRefusals.message(for: r28, port: farLeftPort.observed, overTheAssistant: true)
        .hasSuffix("won't quietly delete something you've made your own. Remove it yourself in Network settings if you're done with it.")
      && RestoreRefusals.message(for: r28, port: farLeftPort.observed, overTheAssistant: false) == r28.body,
      "…and over the picker, where the row has none, ends at the advice")
let r28Replaced = Refusals.createdServiceReplaced(port: farLeftPort.observed)
check(RestoreRefusals.message(for: r28Replaced, port: farLeftPort.observed, overTheAssistant: true)
        == Refusals.createdServiceReplaced(port: farLeftPort.observed, offersStopManaging: false).body
      && RestoreRefusals.message(for: r28Replaced, port: farLeftPort.observed, overTheAssistant: false)
        == r28Replaced.body
      && !RestoreRefusals.message(for: r28Replaced, port: farLeftPort.observed, overTheAssistant: true)
        .contains("changed since"),
      "§6.2 R28's replaced body keeps its own words over the picker, ending at the advice")
check(RestoreRefusals.actions(for: r28Replaced.code) == RestoreRefusals.actions(for: r28.code),
      "…and R28's row, with no default")
var threeThings = twoThings
threeThings.notesWritability = .notWritable(reason: "The folder isn't writable.")
check(PreflightReport(threeThings).groupLabel.map(text) == "Checked — three things to sort out first",
      "§1.3 rule 1: the Checked count comes from the one formatter")

// MARK: §S1, §S9 — RDMALink's service replaced by hand with a full match.

// The service RDMALink made ("MINE") is gone, and one made by hand ("HAND"),
// exactly what RDMALink would have made, stands in its place.
let replacedMatch = snapshot(port("en6", "Back, left middle"),
                             configuration: .readyForRDMA(serviceID: "HAND"), baseline: ownNote)
check(replacedMatch.readiness == .drifted && replacedMatch.hasRDMALinksServiceReplacedByAMatch
      && !replacedMatch.hasRDMALinksOwnServiceEdited && !replacedMatch.readiness.isReady,
      "§S1, §4.3: RDMALink's service replaced by a full match made by hand is drift, never managed")
check(managed.readiness == .managed && !managed.hasRDMALinksServiceReplacedByAMatch,
      "…while RDMALink's own service, still ready, stays managed")
check(ChoosePortReport.route(for: replacedMatch) == .adopt && !PortRowPresentation.offersSetUp(replacedMatch),
      "§S1, R27: it routes to Adopt and is never offered a set-up")
let replacedRow = PortRowPresentation(snapshot: replacedMatch)
check(replacedRow.actions == [.adopt(portID: "en6")]
      && text(replacedRow.detail.state) == "Not set up any more"
      && replacedRow.symbol == "exclamationmark.circle" && replacedRow.symbolStyle == .attention
      && replacedRow.compactBadge == nil,
      "§S1: its row reads Not set up any more and offers Adopt…, with no Ready badge and no Restore…")
check(Situation.drift(replacedMatch).actions == [.adopt(portID: "en6"), .stopManaging(portID: "en6")]
      && Situation.drift(replacedMatch).detail != nil,
      "§S1: the drift row offers the row's Adopt…, keeps Stop Managing…, and RDMALink's service really is gone")
check(picker(replacedMatch).isDimmed && picker(replacedMatch).actions == [.adopt(portID: "en6")]
      && text(picker(replacedMatch).detail.state) == "Set up outside RDMALink"
      && ChoosePortReport.routingLine(for: .adopt, snapshot: replacedMatch).map(text)
        == "This one was set up by hand, and properly. Adopt… looks after it without changing it.",
      "§S4, R27: the picker dims it, reads Set up outside RDMALink, names Adopt… and prints the full match's line")
check(cfg(replacedMatch) == .drift, "§4.3: its ring is drift's")
check(text(ThisMacPresentation.readyRow([replacedMatch, outside]).text)
        == "Ports ready for RDMA — None by RDMALink · two set up outside it"
      && HubPresentation.changedSomethingElse(replacedMatch),
      "§S1: the ready row counts it as set up outside RDMALink, and the note keeps 'Nothing else' off")

// §S9: the full match over the old note, in its own form.
check(AdoptForm(replacedMatch) == .fullMatch(replacing: ownNote)
      && AdoptForm(replacedMatch)?.adoptIsDefault == false
      && AdoptForm(replacedMatch)?.honestyNote.map(text) == AdoptPort.forgottenBridgesHonestyNote,
      "§S9, §2.6: adopting over a note that records bridges says they go, and Adopt is not the default")
let standaloneSetUpNote = PortBaseline(
    bsdName: "en6", receptacle: 1, positionName: "Back, left middle",
    createdService: CreatedServiceRecord(identifier: "MINE", interfaceBSDName: "en6"))
let replacedStandalone = snapshot(port("en6", "Back, left middle"),
                                  configuration: .readyForRDMA(serviceID: "HAND"), baseline: standaloneSetUpNote)
check(replacedStandalone.readiness == .drifted
      && AdoptForm(replacedStandalone)?.adoptIsDefault == true
      && AdoptForm(replacedStandalone)?.honestyNote.map(text) == AdoptPort.replacedNoteHonestyNote,
      "§S9: over a note that records no bridges nothing else goes, and Adopt stays the default")
check(AdoptForm(outside) == .fullMatch(replacing: nil) && AdoptForm(outside)?.adoptIsDefault == true
      && AdoptForm(outside)?.honestyNote.map(text) == AdoptPort.honestyNote,
      "§S9: a port RDMALink never saw keeps the first honesty note")
check(AdoptForm(staleMatch) == .fullMatch(replacing: returnRecord) && AdoptForm(staleMatch)?.adoptIsDefault == true
      && AdoptForm(staleMatch)?.honestyNote.map(text) == AdoptPort.returnRecordHonestyNote,
      "§S9: a port RDMALink returned to the bridge says RDMALink saw it, and Adopt stays the default")
check(AdoptForm(managed) == nil && AdoptForm(adopted) == nil,
      "§S9: a port RDMALink already looks after has nothing to adopt")
check(AdoptForm(driftedNear) == nil && AdoptForm(driftedNearOther) != nil
      && AdoptForm(nearMatch)?.honestyNote == nil && AdoptForm(nearMatch)?.adoptIsDefault == false,
      "§S1, R28: RDMALink's own service edited since is no near match of S9's; a hand-made one is")
let replacedHub = hubModel([farLeftPort, replacedMatch])
check(replacedHub.canPerform(.adopt(portID: "en6")) && replacedHub.canPerform(.stopManaging(portID: "en6"))
      && !replacedHub.canPerform(.returnToBridge(portID: "en6")),
      "the hub's door: Adopt… and Stop Managing…, and no Return to Bridge… over the note's history")
check(replacedHub.canPerform(.restore(portID: "en6"))
      && !PortRowPresentation(snapshot: replacedMatch).actions.contains(.restore(portID: "en6")),
      "§7.4: the row offers no Restore…, and the footer's or the Port menu's still opens the sheet, where R28 answers")
check(!hubModel([farLeftPort, driftedNear]).canPerform(.adopt(portID: "en6")),
      "§2.7: the Port menu's Adopt… is unavailable on RDMALink's own service edited since")

// §S9, "The sheet follows the port": the near match put right with the sheet
// up becomes the full match, and nothing moves once Adopt is pressed.
let openedNear = AdoptForm(driftedNearOther)!
let putRight = AdoptForm(replacedMatch)!
check(AdoptForm.following(openedNear, live: putRight, adopting: false) == .fullMatch(replacing: ownNote),
      "§S9: a near match corrected while the sheet is up becomes the full match, Adopt and all")
check(AdoptForm.following(openedNear, live: nil, adopting: false) == nil
      && AdoptForm.following(putRight, live: nil, adopting: false) == nil,
      "…a port that stops being either keeps the form on screen: the near match its steps, the full match its Adopt, which reads the port again")
let unreadable = snapshot(port("en6", "Back, left middle"), configuration: nil, baseline: ownNote)
check(AdoptForm(unreadable) == nil && AdoptForm.following(putRight, live: AdoptForm(unreadable), adopting: false) == nil,
      "…and a reading that fails for a moment moves nothing")
check(AdoptForm.following(openedNear, live: openedNear, adopting: false) == nil,
      "…the same form stays as it is")
check(AdoptForm.following(openedNear, live: putRight, adopting: true) == nil
      && AdoptForm.following(putRight, live: nil, adopting: true) == nil,
      "…and nothing moves once Adopt is pressed")
let adoptedOverOld = snapshot(port("en6", "Back, left middle"), configuration: .readyForRDMA(serviceID: "HAND"),
                              baseline: PortBaseline.adopted(bsdName: "en6", receptacle: 1,
                                                             positionName: "Back, left middle"))
check(adoptedOverOld.readiness == .adopted && AdoptForm(adoptedOverOld) == nil,
      "adopted, the port is RDMALink's to look after and the sheet has nothing left to switch to")


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
  "$ROOT_DIR/App/Presentation/AdoptPresentation.swift" \
  "$ROOT_DIR/App/Presentation/ChangeLogPresentation.swift" \
  "$ROOT_DIR/App/Model/HubActionsModel.swift" \
  "$ROOT_DIR/App/Model/BurstGate.swift" \
  "$ROOT_DIR/App/Stage/StageMath.swift" \
  "$ROOT_DIR/App/Stage/StageModel.swift" \
  "$ROOT_DIR/App/Stage/StageLegend.swift" \
  "$ROOT_DIR/App/Stage/StageChassisGeometry.swift" \
  "$WORK_DIR/main.swift"

"$WORK_DIR/test_presentation"
# The same assertions under a French locale: §S1's sentences stay English.
"$WORK_DIR/test_presentation" -AppleLocale fr_FR -AppleLanguages "(fr)" >/dev/null
