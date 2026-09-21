//
//  InventoryModel+Hub.swift
//
//  What the hub derives from one reading. Kept out of the model itself so
//  `InventoryModel` stays a reader and every sentence the window prints comes
//  from the pure functions in this folder.
//

import Foundation
import RDMALinkCore

extension InventoryModel {
    /// The RDMA switch, with "restart owed" separated from R22 (§S1, §6.2 R22).
    var switchState: RDMASwitchState {
        ThisMacPresentation.switchState(rdma, hasRestartedSinceSwitchOn: hasRestartedSinceSwitchOn)
    }

    /// S1's headline and body, or R23's read-only copy.
    var hubCopy: HubCopy {
        HubPresentation.copy(hardware: hardware, ports: ports)
    }

    /// The situation rows, in §S1's order.
    var situations: [Situation] {
        HubPresentation.situations(switchState: switchState, ports: ports)
    }

    /// The three `This Mac` rows, top to bottom. The RDMA row is absent while
    /// the switch has not been read; the other two are always observable.
    var thisMacRows: [ThisMacRowModel] {
        var rows: [ThisMacRowModel] = []
        if let rdmaRow = ThisMacPresentation.rdmaRow(switchState) { rows.append(rdmaRow) }
        rows.append(ThisMacPresentation.bridgeRow(ports))
        rows.append(ThisMacPresentation.readyRow(ports))
        return rows
    }

    /// `Copy Details` and `Save a Diagnostics File…` share this payload
    /// (§6.1 rule 8).
    func diagnosticsText(failingStep: String? = nil) -> String {
        Diagnostics.text(
            hardware: hardware,
            ports: ports,
            rdma: rdma,
            switchState: switchState,
            failingStep: failingStep ?? currentFailingStep,
            underlyingReason: lastReadFailure
        )
    }

    /// The step the app is stuck on, named the way the refusal names it.
    private var currentFailingStep: String? {
        switch phase {
        case .noThunderboltHardware: "reading this Mac's Thunderbolt hardware"
        case .unsupportedSystem: "checking the macOS version"
        case .probing, .ready: lastReadFailure == nil ? nil : "reading this Mac"
        }
    }
}
