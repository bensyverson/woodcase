//
//  ServeCommandTests.swift
//  WoodcaseCommandTests
//

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Holds a TCP port open on loopback for the life of the value.
///
/// Used to force a bind collision without touching the real, possibly-shared 7333 —
/// another `woodcase serve`, a person's or another agent's, may already have it. A raw
/// POSIX socket rather than `NWListener` (what `ViewerServer` itself binds with):
/// `NWListener` reproducibly failed every bind attempt with `EINVAL` in this exact
/// suite (confirmed with a standalone script outside SwiftPM too, so it is not a test
/// scheduling artifact) for a reason that did not repay chasing further, since a plain
/// `bind`/`listen` pair needs none of `Network`'s asynchronous readiness machinery to
/// do this one small job.
private final class OccupiedPort {
    /// The port that was bound.
    let port: UInt16
    private let descriptor: Int32

    /// Binds an OS-assigned loopback port and holds it until ``release()``.
    ///
    /// - Throws: If the socket could not be created, bound, or made to listen.
    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let didBind = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                bind(descriptor, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard didBind == 0, listen(descriptor, 1) == 0 else {
            close(descriptor)
            throw CocoaError(.fileWriteUnknown)
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didName = withUnsafeMutablePointer(to: &bound) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                getsockname(descriptor, raw, &length)
            }
        }
        guard didName == 0 else {
            close(descriptor)
            throw CocoaError(.fileWriteUnknown)
        }

        port = UInt16(bigEndian: bound.sin_port)
        self.descriptor = descriptor
    }

    /// Releases the port.
    func release() {
        close(descriptor)
    }
}

/// The `serve` verb, driven as a process.
///
/// `serve` does not end, so the cases that can drive it to completion are the ones that
/// *refuse*: a file that is not there, and `--help`. What the running server does is the
/// viewer target's business and is tested there; what is tested here is the adapter —
/// the flags it accepts, the exit codes it maps to, and that its help works with nothing
/// set up.
struct ServeCommandTests {
    @Test("--help works with no file, no server and no port")
    func helpHasNoPreconditions() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("serve", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("--port"))
        #expect(run.stdout.contains("--open"))
        #expect(run.stdout.contains("Ctrl-C"))
    }

    @Test("The verb is listed in the tool's own primer")
    func verbIsDiscoverable() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--help")

        #expect(run.stdout.contains("serve"))
    }

    @Test("A file that is not there is exit 4 with the command that would show what is")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("serve", fixture.root.appendingPathComponent("nope.pen").path)

        #expect(run.status == 4)
        #expect(run.stderr.contains("no such file"))
        #expect(run.stderr.contains("ls "))
    }

    @Test("A directory named where a file belongs is exit 4, not a hang")
    func directoryIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("serve", fixture.root.path)

        #expect(run.status == 4)
        #expect(run.stderr.contains("it is a directory"))
    }

    @Test("A port that is not a number is a usage error, not a default")
    func badPortIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("serve", "--port", "sixty", fixture.file.path)

        #expect(run.status == 2)
    }

    @Test("With no --port, the flag is unset — the search decides, starting from 7333")
    func defaultPortIsUnset() throws {
        let command = try Serve.parse([])
        #expect(command.port == nil)
        #expect(Serve.defaultPort == 7333)
        #expect(command.files.isEmpty)
        #expect(!command.open)
    }

    @Test("Flags parse in the house's order and shape")
    func flagsParse() throws {
        let command = try Serve.parse(["--port", "0", "--open", "--json", "a.pen", "b.pen"])
        #expect(command.port == 0)
        #expect(command.open)
        #expect(command.output.json)
        #expect(command.files.map(\.path) == ["a.pen", "b.pen"])
    }

    @Test("The started report is the documented shape")
    func startedReportShape() throws {
        let json = try CanonicalJSON.text(
            Serve.Started(url: "http://127.0.0.1:7333/", port: 7333, files: ["/tmp/a.pen"])
        )
        #expect(json.contains("\"url\": \"http://127.0.0.1:7333/\""))
        #expect(json.contains("\"port\": 7333"))
        #expect(json.contains("/tmp/a.pen"))
    }

    // MARK: - Binding

    @Test("A pinned port already in use is a conflict naming the port, not a sandbox denial")
    func pinnedBusyPortIsConflict() throws {
        let occupied = try OccupiedPort()
        defer { occupied.release() }

        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("serve", "--port", String(occupied.port), fixture.file.path)

        #expect(run.status == 3)
        #expect(run.stderr.contains("\(occupied.port)"))
        #expect(run.stderr.lowercased().contains("in use"))
        #expect(!run.stderr.lowercased().contains("sandbox"))
    }

    @Test("Without --port, the search tries the base upward and reports the free one")
    func autoIncrementsPastABusyPort() throws {
        let occupied = try OccupiedPort()
        defer { occupied.release() }

        let fixture = try CommandFixture(fixture: "batch.pen")
        // Plain output, not --json: the JSON report is pretty-printed across several
        // lines, so "the first line" — the one thing safe to read from a process that
        // never exits — would only ever be its opening brace. The bare URL is the one
        // line the report always is.
        let run = try fixture.runInBackground([
            "serve", "--port-base", String(occupied.port), fixture.file.path,
        ])
        defer { run.stop() }

        guard let line = run.firstLine(), let url = URL(string: line), let boundPort = url.port
        else {
            Issue.record("serve did not print a URL before its budget ran out: \(run.stderrText)")
            return
        }
        let bound = UInt16(boundPort)

        #expect(bound != occupied.port)
        #expect(bound > occupied.port)
        #expect(Int(bound) <= Int(occupied.port) + Int(Serve.autoIncrementSpan))
        #expect(line == "http://127.0.0.1:\(bound)/")
    }
}
