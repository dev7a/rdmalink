import Foundation
import Security
import SystemConfiguration

/// Something the network configuration would not do, with the reason macOS gave.
///
/// The apply screen turns these into the spec's refusals: `authorization`
/// cases become R6 (not an administrator) or R7 (no permission given),
/// ``busy`` becomes R12 (another app is editing the network), an expired
/// credential mid-burst becomes R8, and a failed write becomes R10 after
/// rollback.
public enum NetworkConfigurationError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The preferences session could not be opened at all.
    case preferencesUnavailable(Int32)
    /// The user dismissed the macOS password dialog. → R7.
    case authorizationCancelled(OSStatus)
    /// macOS refused the right, or no interaction was allowed. → R6.
    case authorizationDenied(OSStatus)
    /// `AuthorizationCreate` or `AuthorizationCopyRights` failed some other way.
    case authorizationFailed(OSStatus)
    /// System Settings or another writer holds the configuration. → R12.
    case busy(step: String, code: Int32)
    /// A step of the burst failed. → rollback, then R10 or R11.
    case stepFailed(step: String, code: Int32, message: String)
    /// `SCNetworkServiceCreate` refused because the interface is still a
    /// member of a bridge in the **stored** configuration.
    ///
    /// configd answers this with a bare `kSCStatusFailed` (1001), whose
    /// `SCErrorString` is just "Failed!" — so the reason is reconstructed here
    /// from the membership that was read back, rather than left as a number
    /// nobody can act on.
    case interfaceIsStoredBridgeMember(bsdName: String, bridges: [String], code: Int32)
    /// Something that must exist did not, e.g. the interface or the location.
    case missing(String)
    /// The session was used after ``AuthorizedSession/end()`` destroyed its
    /// credential. Always a programming error, never the user's doing.
    case sessionEnded

    /// The `SCError()` code behind this, when there was one.
    public var scStatus: Int32? {
        switch self {
        case let .preferencesUnavailable(code), let .busy(_, code),
             let .stepFailed(_, code, _), let .interfaceIsStoredBridgeMember(_, _, code):
            return code
        default: return nil
        }
    }

    public var description: String {
        switch self {
        case let .preferencesUnavailable(code):
            return "Cannot open network preferences: \(NetworkConfigurationError.message(code))"
        case let .authorizationCancelled(status):
            return "Authorization cancelled (\(status))"
        case let .authorizationDenied(status):
            return "Authorization denied (\(status))"
        case let .authorizationFailed(status):
            return "Authorization failed (\(status))"
        case let .busy(step, code):
            return "\(step): \(NetworkConfigurationError.message(code))"
        case let .stepFailed(step, _, message):
            return "\(step): \(message)"
        case let .interfaceIsStoredBridgeMember(bsdName, bridges, code):
            return "Create the RDMA service: macOS refused "
                + "(\(code) \(NetworkConfigurationError.message(code))) because \(bsdName) is "
                + "still a member of \(bridges.joined(separator: ", ")) in the saved network "
                + "settings, even if the kernel bridge lists no members. The port has to leave "
                + "that bridge first."
        case let .missing(what):
            return "Missing \(what)"
        case .sessionEnded:
            return "The authorized session has already been ended"
        }
    }

    /// The text `SCErrorString` gives for a status code.
    static func message(_ code: Int32) -> String {
        String(cString: SCErrorString(code))
    }

    /// True when the failure is another writer holding the configuration.
    static func isBusy(_ code: Int32) -> Bool {
        code == kSCStatusLocked || code == kSCStatusPrefsBusy || code == kSCStatusNeedLock
    }
}

/// An authorized, locked preferences session: the one burst in which every
/// write of one operation happens.
///
/// `AuthorizationCopyRights` for `system.services.systemconfiguration.network`
/// resolves through `authenticate-admin-nonshared`, which is non-shared and
/// lasts about 30 seconds — so the credential is taken once, immediately
/// before the burst, and every write follows without pausing for the user.
/// `system.preferences.network` is the Network pane's own right and does not
/// satisfy configd.
///
/// Not `Sendable` on purpose: it owns an `AuthorizationRef` and an open
/// `SCPreferences`. Use it from one thread, then ``end()``.
public final class AuthorizedSession {
    /// The authorization right configd requires for network changes.
    public static let right = "system.services.systemconfiguration.network"

    public enum Mode: Sendable, Equatable {
        /// Take the credential, make every change in memory, then throw it all
        /// away: ``commit()`` and ``apply()`` do nothing.
        case dryRun
        /// Commit and apply for real.
        case live
    }

    public let mode: Mode

    /// The open preferences session.
    ///
    /// Deliberately **not** public: configd keeps the `AuthorizationRef` this
    /// handle was created with and serialises it on every commit, so a handle
    /// that outlives ``end()`` would commit through a destroyed credential.
    /// Writes go through the operation types in this module, which reach it
    /// here and nowhere else; everything outside asks the session itself.
    var preferences: SCPreferences {
        get throws {
            guard !isEnded else { throw NetworkConfigurationError.sessionEnded }
            return openPreferences
        }
    }

    private let openPreferences: SCPreferences
    private var authorization: AuthorizationRef?
    private var isLocked = false
    /// True once ``end()`` has destroyed the credential. Nothing works after.
    public private(set) var isEnded = false
    /// True once ``commit()`` has actually written in ``Mode/live``.
    public private(set) var didCommit = false

    private init(mode: Mode, preferences: SCPreferences, authorization: AuthorizationRef?) {
        self.mode = mode
        self.openPreferences = preferences
        self.authorization = authorization
    }

    /// Asks macOS for the network right and opens an authorized session.
    ///
    /// This is the interactive path: it puts up the system password dialog.
    /// Even in ``Mode/dryRun`` the credential is taken, because the point of a
    /// dry run is to prove the whole burst except the final commit.
    public static func begin(
        clientName: String = "RDMALink",
        mode: Mode
    ) throws -> AuthorizedSession {
        var authorization: AuthorizationRef?
        let created = AuthorizationCreate(nil, nil, [], &authorization)
        guard created == errAuthorizationSuccess, let authorization else {
            throw NetworkConfigurationError.authorizationFailed(created)
        }
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights]
        let granted = right.withCString { name -> OSStatus in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(authorization, &rights, nil, flags, nil)
            }
        }
        guard granted == errAuthorizationSuccess else {
            AuthorizationFree(authorization, [])
            switch granted {
            case errAuthorizationCanceled:
                throw NetworkConfigurationError.authorizationCancelled(granted)
            case errAuthorizationDenied, errAuthorizationInteractionNotAllowed:
                throw NetworkConfigurationError.authorizationDenied(granted)
            default:
                throw NetworkConfigurationError.authorizationFailed(granted)
            }
        }
        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil, clientName as CFString, nil, authorization
        ) else {
            let code = SCError()
            AuthorizationFree(authorization, [])
            throw NetworkConfigurationError.preferencesUnavailable(code)
        }
        return AuthorizedSession(mode: mode, preferences: preferences,
                                 authorization: authorization)
    }

    /// Takes the configuration lock. Fails rather than waits: two writers is
    /// how configurations get mangled.
    public func lock() throws {
        let preferences = try preferences
        guard !isLocked else { return }
        guard SCPreferencesLock(preferences, false) else {
            let code = SCError()
            if NetworkConfigurationError.isBusy(code) {
                throw NetworkConfigurationError.busy(step: "Lock network preferences", code: code)
            }
            throw NetworkConfigurationError.stepFailed(
                step: "Lock network preferences", code: code,
                message: NetworkConfigurationError.message(code))
        }
        isLocked = true
    }

    /// Writes the session's changes to disk. A no-op in ``Mode/dryRun``.
    public func commit() throws {
        let preferences = try preferences
        guard mode == .live else { return }
        try check(SCPreferencesCommitChanges(preferences), "Commit network preferences")
        didCommit = true
    }

    /// Tells configd to adopt what was committed. A no-op in ``Mode/dryRun``.
    public func apply() throws {
        let preferences = try preferences
        guard mode == .live else { return }
        try check(SCPreferencesApplyChanges(preferences), "Apply network preferences")
    }

    /// Every network service this session can see. The one read the outside
    /// needs, so the preferences handle itself never has to leave the module.
    public func services() throws -> [NetworkServiceInfo] {
        NetworkServices.read(from: try preferences)
    }

    /// Releases the configuration lock. Safe to call twice.
    public func unlock() {
        guard isLocked, !isEnded else { return }
        SCPreferencesUnlock(openPreferences)
        isLocked = false
    }

    /// Unlocks and destroys the credential. The session must not be used after.
    public func end() {
        guard !isEnded else { return }
        unlock()
        if let authorization {
            AuthorizationFree(authorization, [.destroyRights])
            self.authorization = nil
        }
        isEnded = true
    }

    deinit { end() }

    /// Turns a SystemConfiguration `false` into the reason macOS gave.
    func check(_ succeeded: Bool, _ step: String) throws {
        guard !succeeded else { return }
        let code = SCError()
        if NetworkConfigurationError.isBusy(code) {
            throw NetworkConfigurationError.busy(step: step, code: code)
        }
        throw NetworkConfigurationError.stepFailed(
            step: step, code: code, message: NetworkConfigurationError.message(code))
    }
}
