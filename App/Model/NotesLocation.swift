//
//  NotesLocation.swift
//
//  Where RDMALink's own two files live: the notes folder and the change log
//  (UX_SPEC §7.1, §S11). The app's folder in Application Support, or the one
//  `RDMALINK_APPLICATION_SUPPORT` names — the same override the `rdmalink`
//  tool honours, for reads **and** writes — so a reviewer can show the app a
//  folder of notes without touching the real ones (App/SnapshotHook.swift).
//  Every read of a note, every operation's note and log, and R14's
//  writability check go through here, so the app never reads its notes from
//  one folder and writes them to another. Nothing here writes on its own.
//

import Foundation
import RDMALinkCore

enum NotesLocation {
    static let directory: URL = ProcessInfo.processInfo.environment["RDMALINK_APPLICATION_SUPPORT"]
        .map { URL(fileURLWithPath: $0) } ?? BaselineStore.applicationDirectory

    /// Exactly the folder `Show Notes in Finder` reveals.
    static var store: BaselineStore {
        BaselineStore(directory: directory.appending(path: BaselineStore.notesFolderName))
    }

    static var changeLog: ChangeLog {
        ChangeLog(url: directory.appending(path: ChangeLog.fileName))
    }

    /// What every operation needs that is not the world and not the port,
    /// with its note and log in this folder.
    static func environment(hardware: HardwareModel) -> OperationEnvironment {
        OperationEnvironment(hardware: hardware, store: store, log: changeLog)
    }
}
