import Darwin
import Foundation

/// Runs one of the small system tools the app reads its state from.
///
/// Every rule here earns its place: `posix_spawn` with standard input closed,
/// an unlinked temporary file for the output so no inherited writer can hold
/// the parent open, a deadline with `TERM` and then `KILL`, and a hard cap on
/// how much output is accepted. Nothing here writes anything: the runner
/// exists so `nvram`, `ibv_devices` and `ifconfig` can be read without a
/// `Process` object that may outlive its caller.
///
/// The call blocks for up to `timeout`, so callers on the main actor run it in
/// a task of their own.
public struct CommandRunner: Sendable {

    /// What a tool printed, and the status it exited with.
    public struct Output: Sendable, Equatable {
        /// The exit status, or 128 + signal number when the tool was signalled.
        public var exitStatus: Int32
        /// Standard output and standard error, interleaved as the tool wrote them.
        public var text: String

        public init(exitStatus: Int32, text: String) {
            self.exitStatus = exitStatus
            self.text = text
        }

        /// True when the tool exited zero.
        public var succeeded: Bool { exitStatus == 0 }
    }

    /// Why a tool could not be run to completion. These strings are technical
    /// on purpose: they end up in `Copy Details`, never in a headline.
    public enum Failure: Error, Sendable, Equatable, CustomStringConvertible {
        /// The path is not one of the system tool directories, or is not absolute.
        case notAllowed(path: String)
        /// `posix_spawn` refused, usually because the tool is not installed.
        case cannotStart(path: String, code: Int32)
        /// The tool was still running after the deadline and was killed.
        case timedOut(path: String, seconds: Double)
        /// The tool printed more than `maximumOutputBytes`.
        case tooMuchOutput(path: String, limit: Int)
        /// A file or wait operation failed while running the tool.
        case io(String)

        public var description: String {
            switch self {
            case .notAllowed(let path):
                "\(path) is not a system tool in /bin, /sbin, /usr/bin or /usr/sbin"
            case .cannotStart(let path, let code):
                "Cannot start \(path) (\(code))"
            case .timedOut(let path, let seconds):
                "\(path) timed out after \(seconds) seconds"
            case .tooMuchOutput(let path, let limit):
                "\(path) printed more than \(limit) bytes"
            case .io(let reason):
                reason
            }
        }
    }

    /// The only directories a tool may live in.
    public static let allowedDirectories = ["/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/"]

    /// How long a tool may take before it is signalled.
    public var timeout: Duration
    /// How much output is accepted before the run is refused.
    public var maximumOutputBytes: Int

    public init(timeout: Duration = .seconds(5), maximumOutputBytes: Int = 1024 * 1024) {
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    /// True when `path` is an absolute path to a file in one of the system
    /// tool directories, with no relative component in it.
    public static func isAllowed(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        guard let directory = allowedDirectories.first(where: { path.hasPrefix($0) }) else { return false }
        let name = path.dropFirst(directory.count)
        return !name.isEmpty && !name.contains("/")
    }

    /// Runs `path` with `arguments` and returns what it printed.
    ///
    /// - Throws: ``Failure`` when the tool could not be started, overran the
    ///   deadline, or printed more than the cap. An ordinary nonzero exit is
    ///   not a failure: it comes back in ``Output/exitStatus``.
    public func run(_ path: String, _ arguments: [String] = []) throws -> Output {
        guard Self.isAllowed(path) else { throw Failure.notAllowed(path: path) }

        // An unlinked temporary file: the output is readable after the child
        // exits without waiting for EOF from any descriptor it passed on.
        var template = Array((NSTemporaryDirectory() + "rdmalink-command.XXXXXX").utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw Failure.io("Cannot capture command output") }
        defer { close(descriptor) }
        guard unlink(CBuffer.string(template)) == 0 else {
            throw Failure.io("Cannot unlink command output")
        }
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw Failure.io("Cannot protect the command output descriptor")
        }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw Failure.io("Cannot initialize command file actions")
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        let redirected = "/dev/null".withCString {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, $0, O_RDONLY, 0)
        } == 0
            && posix_spawn_file_actions_adddup2(&actions, descriptor, STDOUT_FILENO) == 0
            && posix_spawn_file_actions_adddup2(&actions, descriptor, STDERR_FILENO) == 0
        guard redirected else { throw Failure.io("Cannot configure command output") }

        let argumentPointers = ([path] + arguments).map { strdup($0) }
        defer { argumentPointers.forEach { free($0) } }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        let environmentPointers = environment.map { strdup($0.key + "=" + $0.value) }
        defer { environmentPointers.forEach { free($0) } }
        guard argumentPointers.allSatisfy({ $0 != nil }), environmentPointers.allSatisfy({ $0 != nil }) else {
            throw Failure.io("Cannot allocate the command arguments")
        }
        var argv = argumentPointers + [nil]
        var envp = environmentPointers + [nil]

        var child: pid_t = 0
        let spawnStatus = path.withCString { executable in
            argv.withUnsafeMutableBufferPointer { argumentBuffer in
                envp.withUnsafeMutableBufferPointer { environmentBuffer in
                    posix_spawn(&child, executable, &actions, nil,
                                argumentBuffer.baseAddress, environmentBuffer.baseAddress)
                }
            }
        }
        guard spawnStatus == 0 else { throw Failure.cannotStart(path: path, code: spawnStatus) }

        var ownsChild = true
        defer {
            if ownsChild {
                // A child stuck in the kernel must not hold the caller past the
                // final deadline. One waiter stays behind to reap it, so its
                // process id can never be reused while signals are in flight.
                _ = Darwin.kill(child, SIGKILL)
                let ownedChild = child
                DispatchQueue.global(qos: .utility).async {
                    var status: Int32 = 0
                    while Darwin.waitpid(ownedChild, &status, 0) < 0 && errno == EINTR {}
                }
            }
        }

        func wait(until deadline: DispatchTime) throws -> Int32? {
            while true {
                var status: Int32 = 0
                let result = Darwin.waitpid(child, &status, WNOHANG)
                if result == child {
                    ownsChild = false
                    return status
                }
                if result < 0 {
                    if errno == EINTR { continue }
                    if errno == ECHILD { ownsChild = false }
                    throw Failure.io("Cannot wait for \(path) (\(errno))")
                }
                let now = DispatchTime.now()
                if now >= deadline { return nil }
                let remaining = (deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000
                _ = Darwin.poll(nil, 0, Int32(max(1, min(10, remaining))))
            }
        }

        let seconds = Self.seconds(timeout)
        guard let status = try wait(until: .now() + .nanoseconds(Int(seconds * 1_000_000_000))) else {
            _ = Darwin.kill(child, SIGTERM)
            if try wait(until: .now() + .milliseconds(250)) == nil {
                _ = Darwin.kill(child, SIGKILL)
                _ = try wait(until: .now() + .milliseconds(250))
            }
            throw Failure.timedOut(path: path, seconds: seconds)
        }

        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= 0 else {
            throw Failure.io("Cannot inspect \(path) output")
        }
        guard info.st_size <= maximumOutputBytes else {
            throw Failure.tooMuchOutput(path: path, limit: maximumOutputBytes)
        }
        let count = Int(info.st_size)
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = data.withUnsafeMutableBytes {
                guard let base = $0.baseAddress else { return -1 }
                return Darwin.pread(descriptor, base.advanced(by: offset), count - offset, off_t(offset))
            }
            if readCount < 0 && errno == EINTR { continue }
            guard readCount > 0 else { throw Failure.io("Cannot read \(path) output") }
            offset += readCount
        }

        let exited = status & 0x7f == 0
        let exitStatus = exited ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return Output(exitStatus: exitStatus, text: String(decoding: data, as: UTF8.self))
    }

    /// The deadline in seconds, never below a millisecond.
    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return max(0.001, value)
    }
}
