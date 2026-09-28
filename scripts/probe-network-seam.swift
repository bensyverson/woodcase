// probe-network-seam.swift — what Network.framework actually does at the viewer's seam.
//
//   swift scripts/probe-network-seam.swift     (sandbox off; see project/agents/harness.md)
//
// The viewer's HTTP server awaits three Network.framework callbacks, and an await on a
// callback that never arrives is invisible: a suspended Swift task has no thread and no
// stack, so a wedged process samples with no frame of ours in it. This probe answers,
// by observation rather than by documentation, which of those callbacks can fail to
// arrive — and it is what root-caused the `NWListener` EINVAL entry in project/gotchas.md.
//
// It prints one VERDICT line per question and exits. Every wait is bounded, so the probe
// itself cannot hang.
//
//   L1 An NWListener with HTTPServer.start's exact parameters, started with **no**
//      newConnectionHandler.  (Observed 2026-08-31, macOS 26.5.2: .failed(POSIXErrorCode
//      22), every time — this is the whole of the old "NWListener EINVAL" mystery.)
//   L2 The same listener with a newConnectionHandler set before start.  (.ready.)
//   S1 Does a send's .contentProcessed completion fire when the connection is cancelled
//      while the send is in flight?  (Yes.)
//   S2 Does it fire for a send issued on an already-cancelled connection?  (Yes.)
//
// A "no" from S1 or S2 would mean HTTPConnection's writes can be unresumable by
// cancellation, which would change where the viewer's give-up budget has to live.

import Darwin
import Dispatch
import Foundation
import Network

let queue = DispatchQueue(label: "probe")

func verdict(_ name: String, _ text: String) {
    print("VERDICT \(name): \(text)")
    fflush(stdout)
}

/// A lock around a value, so a callback on any queue can report through it.
final class Box<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }; return value
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); body(&value); lock.unlock()
    }
}

/// `HTTPServer.start(port: 0)`'s parameters, exactly.
func loopbackParameters() -> NWParameters {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
    return parameters
}

// MARK: - L: which listener state is reached

/// - Parameters:
///   - name: The verdict's label.
///   - acceptsConnections: Whether a `newConnectionHandler` is set before `start`. This
///     is the variable that decides the answer.
func probeListener(_ name: String, acceptsConnections: Bool) {
    guard let listener = try? NWListener(using: loopbackParameters()) else {
        verdict(name, "NWListener(using:) threw for the viewer's own parameters")
        return
    }
    if acceptsConnections {
        listener.newConnectionHandler = { _ in }
    }
    let settled = DispatchSemaphore(value: 0)
    let states = Box<[String]>([])
    let once = Box(false)
    listener.stateUpdateHandler = { state in
        states.mutate { $0.append("\(state)") }
        switch state {
        case .ready, .failed:
            var already = false
            once.mutate { already = $0; $0 = true }
            if !already { settled.signal() }
        default:
            break
        }
    }
    listener.start(queue: queue)
    let outcome = settled.wait(timeout: .now() + 8)
    let observed = states.get().joined(separator: " -> ")
    listener.cancel()
    if outcome == .timedOut {
        verdict(name, "UNSETTLED after 8 s — states [\(observed)]. An unbounded "
            + "HTTPServer.start would still be suspended here.")
    } else {
        verdict(name, "settled — states [\(observed)] "
            + "port=\(listener.port?.rawValue.description ?? "nil")")
    }
}

// MARK: - S1 / S2: does a send completion arrive

/// Hands `body` an accepted, ready inbound connection plus the raw client socket at the
/// other end of it, then tears both down.
func withAcceptedConnection(_ body: (NWConnection, Int32) -> Void) {
    guard let listener = try? NWListener(using: loopbackParameters()) else {
        verdict("S", "no listener — run L first to see why")
        return
    }
    let ready = DispatchSemaphore(value: 0)
    let accepted = DispatchSemaphore(value: 0)
    let held = Box<NWConnection?>(nil)
    listener.newConnectionHandler = { connection in
        held.mutate { $0 = connection }
        connection.start(queue: queue)
        accepted.signal()
    }
    listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + 10) == .success, let port = listener.port?.rawValue else {
        verdict("S", "listener never became ready — run L first to see why")
        listener.cancel()
        return
    }

    let client = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            _ = connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard accepted.wait(timeout: .now() + 10) == .success, let connection = held.get() else {
        verdict("S", "nothing was accepted")
        listener.cancel()
        close(client)
        return
    }
    let up = DispatchSemaphore(value: 0)
    let once = Box(false)
    connection.stateUpdateHandler = { state in
        var already = false
        if case .ready = state {
            once.mutate { already = $0; $0 = true }
            if !already { up.signal() }
        }
    }
    _ = up.wait(timeout: .now() + 10)

    body(connection, client)
    listener.cancel()
    close(client)
}

func probeCancelInFlight() {
    withAcceptedConnection { connection, client in
        // Shrink the peer's receive window and never read, so the send cannot finish on
        // its own, then cancel underneath it.
        var size: Int32 = 4096
        setsockopt(client, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let done = DispatchSemaphore(value: 0)
        connection.send(
            content: Data(count: 32 * 1024 * 1024),
            completion: .contentProcessed { _ in done.signal() }
        )
        queue.asyncAfter(deadline: .now() + 0.3) { connection.cancel() }
        if done.wait(timeout: .now() + 8) == .timedOut {
            verdict("S1", "completion NEVER fired for a send cancelled in flight")
        } else {
            verdict("S1", "completion fired for a send cancelled in flight")
        }
    }
}

func probeSendAfterCancel() {
    withAcceptedConnection { connection, _ in
        connection.cancel()
        Thread.sleep(forTimeInterval: 0.3)
        let done = DispatchSemaphore(value: 0)
        connection.send(
            content: Data("hello".utf8),
            completion: .contentProcessed { _ in done.signal() }
        )
        if done.wait(timeout: .now() + 8) == .timedOut {
            verdict("S2", "completion NEVER fired for a send on a cancelled connection")
        } else {
            verdict("S2", "completion fired for a send on a cancelled connection")
        }
    }
}

probeListener("L1 (no newConnectionHandler)", acceptsConnections: false)
probeListener("L2 (newConnectionHandler set)", acceptsConnections: true)
probeCancelInFlight()
probeSendAfterCancel()
