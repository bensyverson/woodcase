//
//  ViewerServerTests.swift
//  WoodcaseViewerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The whole viewer, driven over a real socket with `URLSession` — the one test that
/// proves the pieces are wired to each other and not merely to their own unit tests.
@Suite(.hangGuard)
struct ViewerServerTests {
    /// Collects Server-Sent Events off a live stream.
    private actor Stream {
        private(set) var frames: [(name: String, data: String)] = []
        private(set) var finished = false

        func record(name: String, data: String) {
            frames.append((name, data))
        }

        func finish() {
            finished = true
        }

        func changes() -> [ViewerChange] {
            frames.compactMap { frame in
                guard frame.name == SSEEvent.Name.change.rawValue else { return nil }
                return try? ViewerJSON.decoder.decode(ViewerChange.self, from: Data(frame.data.utf8))
            }
        }

        func presence() -> [ViewerPresence] {
            frames.compactMap { frame in
                guard frame.name == SSEEvent.Name.presence.rawValue else { return nil }
                return try? ViewerJSON.decoder.decode(ViewerPresence.self, from: Data(frame.data.utf8))
            }
        }

        /// Reads the stream until it ends, assembling one frame per blank line.
        ///
        /// Byte by byte rather than through `AsyncLineSequence`, because that sequence
        /// drops empty lines — and an empty line is exactly what ends an SSE frame.
        func consume(_ url: URL, session: URLSession) async {
            guard let (bytes, _) = try? await session.bytes(from: url) else {
                finish()
                return
            }
            var pending: [UInt8] = []
            do {
                for try await byte in bytes {
                    pending.append(byte)
                    guard pending.count >= 2,
                          pending[pending.count - 1] == 0x0A,
                          pending[pending.count - 2] == 0x0A
                    else { continue }
                    parse(String(decoding: pending, as: UTF8.self))
                    pending.removeAll(keepingCapacity: true)
                }
            } catch {
                // The server closing the stream is how this ends.
            }
            finish()
        }

        /// Records one complete frame. A heartbeat comment carries neither name nor data.
        private func parse(_ frame: String) {
            var name = "message"
            var data: [String] = []
            for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("event: ") {
                    name = String(line.dropFirst("event: ".count))
                } else if line.hasPrefix("data: ") {
                    data.append(String(line.dropFirst("data: ".count)))
                }
            }
            guard !data.isEmpty else { return }
            record(name: name, data: data.joined(separator: "\n"))
        }
    }

    /// A running server over a copy of `batch.pen`, with its own activity log.
    private struct Bench {
        let scratch: URL
        let file: URL
        let log: ActivityLog
        let server: ViewerServer
        let port: UInt16
        let session: URLSession

        init() async throws {
            scratch = try ViewerFixtures.scratch()
            file = try ViewerFixtures.copy("batch.pen", into: scratch)
            log = ActivityLog(home: scratch)
            server = ViewerServer()
            port = try await server.start(files: [file], port: 0, log: log)
            let configuration = URLSessionConfiguration.ephemeral
            // A failure here should read as a failure, not as a minute of silence.
            configuration.timeoutIntervalForRequest = ViewerFixtures.requestBudget
            session = URLSession(configuration: configuration)
        }

        var fileID: String {
            ViewerFile(url: file).id
        }

        func url(_ path: String) -> URL {
            URL(string: "http://127.0.0.1:\(port)\(path)")!
        }

        func get(_ path: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url(path))
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            return (data, response as! HTTPURLResponse)
        }

        func stop() async {
            await server.stop()
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    @Test("Port 0 binds whatever is free and the server reports it")
    func bindsAnEphemeralPort() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        #expect(bench.port != 0)
        #expect(await bench.server.port == bench.port)
        #expect(await bench.server.address?.absoluteString == "http://127.0.0.1:\(bench.port)/")
    }

    @Test("GET /files lists the served file over HTTP")
    func servesTheFileList() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (data, response) = try await bench.get("/files")
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")

        let report = try ViewerJSON.decoder.decode(FileListReport.self, from: data)
        #expect(report.files.map(\.id) == [bench.fileID])
        #expect(report.files[0].artboards.map(\.id) == ["Cnv01", "Brd01", "Cmp01"])
    }

    @Test("GET tree.json over HTTP is the tree verb's --json form, byte for byte")
    func servesTheTree() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let expected = try await PenFileTransaction.read(at: bench.file, timeout: ViewerFixtures.lockBudget) { document in
            try TreeFormatter.json(TreeView.rows(of: document), revision: document.documentRevision)
        }.value

        let (data, response) = try await bench.get("/files/\(bench.fileID)/tree.json")
        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == expected)
    }

    @Test("GET an artboard's PNG over HTTP decodes at the artboard's size")
    func servesAPNG() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (data, response) = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01.png?max=400")
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "image/png")

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 400)
        #expect(image.height == 300)
    }

    @Test("A path nothing serves is a 404 whose body says what to try")
    func explainsA404() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (data, response) = try await bench.get("/nope")
        #expect(response.statusCode == 404)
        #expect(String(decoding: data, as: UTF8.self).contains("GET / lists the endpoints"))
    }

    @Test("Editing a watched file pushes a change over SSE and the PNG that follows is new")
    func pushesAChange() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (before, _) = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01.png")

        let stream = Stream()
        let consumer = Task { await stream.consume(bench.url("/events"), session: bench.session) }
        defer { consumer.cancel() }
        // The greeting proves the stream is live before the edit is made.
        await waitUntil("the stream to be greeted with presence") {
            await !stream.presence().isEmpty
        }

        try await PenFileTransaction.run(at: bench.file, identity: "tester", log: bench.log, timeout: ViewerFixtures.lockBudget) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Cnv01", properties: ["kind.width": .int(500)]
            )))
        }

        await waitUntil("a change event attributed to the edit") {
            await stream.changes().contains { $0.identity == "tester" }
        }

        let change = try #require(await stream.changes().last { $0.identity == "tester" })
        #expect(change.file == bench.fileID)
        #expect(change.artboards == ["Cnv01", "Brd01", "Cmp01"])
        #expect(change.nodes == ["Cnv01"])
        #expect(change.op == .set)
        #expect(!change.revision.isEmpty)

        let (after, _) = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01.png")
        #expect(after != before)
    }

    @Test("Startup warms the map's thumbnails, so a first map load is not a wall of boxes")
    func warmsTheMapThumbnails() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let renders = try #require(await bench.server.context).renders
        let file = ViewerFile(url: bench.file)
        await waitUntil("every artboard's map thumbnail to be warm") {
            for artboard in ["Cnv01", "Brd01", "Cmp01"] {
                let warm = await renders.isRendered(
                    artboard: artboard, of: file, longestSide: ArtboardMap.thumbnailEdge
                )
                if !warm { return false }
            }
            return true
        }
    }

    @Test("Stopping the server closes the open event streams")
    func stopClosesStreams() async throws {
        let bench = try await Bench()
        let scratch = bench.scratch
        defer { try? FileManager.default.removeItem(at: scratch) }

        let stream = Stream()
        let consumer = Task { await stream.consume(bench.url("/events"), session: bench.session) }
        defer { consumer.cancel() }
        await waitUntil("the stream to be greeted") { await !stream.presence().isEmpty }

        await bench.server.stop()

        await waitUntil("the stream to end") { await stream.finished }
        bench.session.invalidateAndCancel()
    }
}
