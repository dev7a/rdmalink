import Foundation
import SystemConfiguration

/// Wakes the caller when a Thunderbolt port's link or address state changes.
///
/// `State:/Network/Interface/<bsd>/Link` (and `/IPv6`) is the only public live
/// event for a Thunderbolt-IP port, and it fires on link transitions only: a
/// dock arriving or leaving may produce nothing at all. A poll tick therefore
/// runs underneath, so a caller that re-reads the inventory on every yield sees
/// every change within `pollInterval` even when the store stays silent.
///
/// The stream yields `Void`: it is a "look again" signal, not a diff. The
/// caller re-reads ``PortInventory`` and decides what changed.
public struct LinkWatcher: Sendable {
    /// The BSD names to subscribe to, from ``PortInventory/read(archetype:)``.
    public var bsdNames: [String]
    /// The backstop tick. ARCHITECTURE.md specifies one second.
    public var pollInterval: Duration

    public init(bsdNames: [String], pollInterval: Duration = .seconds(1)) {
        self.bsdNames = bsdNames
        self.pollInterval = pollInterval
    }

    /// A stream that yields once per store notification and once per tick.
    ///
    /// Cancelling the consuming task, or letting the stream go, unsubscribes
    /// the store and cancels the timer. Yields coalesce: a caller that is slow
    /// to re-read never accumulates a backlog of stale wake-ups.
    public func changes() -> AsyncStream<Void> {
        let names = bsdNames
        let interval = pollInterval
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let session = WatchSession(continuation: continuation)
            continuation.onTermination = { _ in session.stop() }
            session.start(bsdNames: names, interval: interval)
        }
    }
}

/// Owns the `SCDynamicStore` subscription and the poll timer for one stream.
///
/// Unchecked because it stores an `SCDynamicStore`, which Core Foundation does
/// not declare `Sendable`. Every access to it is under `lock`, and the store is
/// only ever handed to SystemConfiguration itself.
private final class WatchSession: @unchecked Sendable {
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "com.dev7a.RDMALink.LinkWatcher")
    private let lock = NSLock()
    private var store: SCDynamicStore?
    private var timer: DispatchSourceTimer?
    /// The `+1` handed to the store's callback context, released on stop.
    private var callbackReference: Unmanaged<WatchSession>?
    private var stopped = false

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    func start(bsdNames: [String], interval: Duration) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        subscribe(to: bsdNames)
        tick(every: interval)
    }

    func stop() {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        stopped = true
        let store = self.store
        let timer = self.timer
        let reference = callbackReference
        self.store = nil
        self.timer = nil
        callbackReference = nil
        lock.unlock()

        // Outside the lock: unsubscribing drains the notification queue, and
        // the callback must never find the lock held against it.
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        timer?.cancel()
        continuation.finish()
        reference?.release()
    }

    /// Called from the store's callback and from the timer.
    fileprivate func fire() {
        continuation.yield()
    }

    private func subscribe(to bsdNames: [String]) {
        let keys = bsdNames.flatMap { name -> [String] in
            [kSCEntNetLink, kSCEntNetIPv6].compactMap { entity in
                SCDynamicStoreKeyCreateNetworkInterfaceEntity(
                    nil, kSCDynamicStoreDomainState, name as CFString, entity
                ) as String?
            }
        }
        guard !keys.isEmpty else { return }
        let reference = Unmanaged.passRetained(self)
        var context = SCDynamicStoreContext(
            version: 0,
            info: reference.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<WatchSession>.fromOpaque(info).takeUnretainedValue().fire()
        }
        guard let store = SCDynamicStoreCreate(
            nil, "com.dev7a.RDMALink.LinkWatcher" as CFString, callback, &context
        ) else {
            reference.release()
            return
        }
        guard SCDynamicStoreSetNotificationKeys(store, keys as CFArray, nil) else {
            reference.release()
            return
        }
        SCDynamicStoreSetDispatchQueue(store, queue)
        self.store = store
        callbackReference = reference
    }

    private func tick(every interval: Duration) {
        let seconds = Double(interval.components.seconds)
            + Double(interval.components.attoseconds) * 1e-18
        guard seconds > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + seconds, repeating: seconds, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.fire() }
        timer.resume()
        self.timer = timer
    }
}
