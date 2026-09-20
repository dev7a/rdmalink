import Foundation
import Testing
@testable import RDMALinkCore

@Suite("Command runner")
struct StatusCommandRunnerTests {

    @Test("Only the system tool directories")
    func allowsOnlySystemTools() {
        #expect(CommandRunner.isAllowed("/usr/bin/ibv_devices"))
        #expect(CommandRunner.isAllowed("/usr/sbin/nvram"))
        #expect(CommandRunner.isAllowed("/sbin/ifconfig"))
        #expect(CommandRunner.isAllowed("/bin/echo"))
        #expect(!CommandRunner.isAllowed("/usr/local/bin/nvram"))
        #expect(!CommandRunner.isAllowed("ifconfig"))
        #expect(!CommandRunner.isAllowed("/usr/bin/../../tmp/tool"))
        #expect(!CommandRunner.isAllowed("/usr/bin/sub/tool"))
        #expect(!CommandRunner.isAllowed("/usr/bin/"))
    }

    @Test("Something outside them is refused before it runs")
    func refusesOtherPaths() {
        #expect(throws: CommandRunner.Failure.notAllowed(path: "/usr/local/bin/tool")) {
            try CommandRunner().run("/usr/local/bin/tool")
        }
    }

    @Test("What the tool printed comes back")
    func capturesOutput() throws {
        let output = try CommandRunner().run("/bin/echo", ["hello"])
        #expect(output.succeeded)
        #expect(output.text == "hello\n")
    }

    @Test("An ordinary nonzero exit is not a failure")
    func reportsExitStatus() throws {
        let output = try CommandRunner().run("/usr/bin/false")
        #expect(!output.succeeded)
        #expect(output.exitStatus == 1)
    }

    @Test("A tool that is not installed cannot start")
    func reportsMissingTool() {
        #expect(throws: CommandRunner.Failure.self) {
            try CommandRunner().run("/usr/bin/rdmalink-no-such-tool")
        }
    }

    @Test("A tool that will not finish is killed on the deadline")
    func killsOnTheDeadline() throws {
        let runner = CommandRunner(timeout: .milliseconds(200))
        let started = Date()
        #expect(throws: CommandRunner.Failure.self) {
            try runner.run("/bin/sleep", ["30"])
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("Too much output is refused rather than buffered")
    func boundsOutput() {
        let runner = CommandRunner(maximumOutputBytes: 64)
        #expect(throws: CommandRunner.Failure.tooMuchOutput(path: "/bin/dd", limit: 64)) {
            try runner.run("/bin/dd", ["if=/dev/zero", "bs=1024", "count=1"])
        }
    }
}
