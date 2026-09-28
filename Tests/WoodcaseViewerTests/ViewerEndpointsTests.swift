//
//  ViewerEndpointsTests.swift
//  WoodcaseViewerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import Woodcase
@testable import WoodcaseViewer

@Suite(.hangGuard)
struct ViewerEndpointsTests {
    /// A scratch directory holding a copy of `batch.pen`, plus a context over it.
    private struct Bench {
        let scratch: URL
        let file: URL
        let context: ViewerContext

        init() throws {
            scratch = try ViewerFixtures.scratch()
            file = try ViewerFixtures.copy("batch.pen", into: scratch)
            context = ViewerFixtures.context(files: [file], home: scratch)
        }

        func request(
            _ path: String,
            query: [String: String] = [:],
            parameters: [String: String] = [:]
        ) -> ViewerRequest {
            ViewerRequest(
                http: HTTPRequest(
                    method: .get, path: path, query: query, headers: [:], target: path
                ),
                parameters: parameters,
                context: context
            )
        }

        func fileID() -> String {
            ViewerFile(url: file).id
        }

        func clean() {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    private func body(of response: HTTPResponse) throws -> Data {
        guard case let .data(data) = response.body else {
            throw ViewerError.malformedTheme("expected a data body")
        }
        return data
    }

    // MARK: - /files

    @Test("GET /files lists each file with its artboards at their settled sizes and canvas positions")
    func listsFiles() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.files(bench.request("/files"))
        let report = try ViewerJSON.decoder.decode(FileListReport.self, from: body(of: response))

        #expect(report.files.count == 1)
        let summary = try #require(report.files.first)
        #expect(summary.id == bench.fileID())
        #expect(summary.name == "batch")
        #expect(summary.error == nil)
        #expect(summary.revision?.isEmpty == false)
        // Every top-level frame after expansion, definitions included: `Component` is
        // reusable and never placed, and it is still an artboard, because a definition
        // is what a designer edits. See ``ComponentArtboardTests``.
        #expect(summary.artboards.map(\.name) == ["Canvas", "Board", "Component"])
        #expect(summary.artboards.map(\.width) == [400, 200, 60])
        #expect(summary.artboards.map(\.height) == [300, 100, 24])
        // Where each one sits on the canvas — what the bird's-eye map draws from.
        #expect(summary.artboards.map(\.x) == [0, 500, 0])
        #expect(summary.artboards.map(\.y) == [0, 40, 400])
    }

    @Test("GET /files carries the last logged edit, with who made it")
    func listsLastChange() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        try await PenFileTransaction.run(
            at: bench.file, identity: "ana", log: ActivityLog(home: bench.scratch),
            timeout: ViewerFixtures.lockBudget
        ) { document, recorder in
            let node = try #require(document.nodes["Ttl01"])
            var common = node.common
            common.name = "Retitled"
            try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Ttl01", common: common)))
        }

        let response = try await ViewerEndpoints.files(bench.request("/files"))
        let report = try ViewerJSON.decoder.decode(FileListReport.self, from: body(of: response))
        let change = try #require(report.files.first?.lastChange)
        #expect(change.identity == "ana")
        #expect(change.op == .set)
        #expect(change.nodes == ["Ttl01"])
    }

    @Test("A file that cannot be parsed is listed with its error, not left out")
    func listsBrokenFiles() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let broken = scratch.appendingPathComponent("broken.pen")
        try Data("not json".utf8).write(to: broken)
        let context = ViewerFixtures.context(files: [broken], home: scratch)

        let response = try await ViewerEndpoints.files(ViewerRequest(
            http: HTTPRequest(method: .get, path: "/files", query: [:], headers: [:], target: "/files"),
            parameters: [:],
            context: context
        ))
        let report = try ViewerJSON.decoder.decode(FileListReport.self, from: body(of: response))
        #expect(report.files.count == 1)
        #expect(report.files[0].error != nil)
        #expect(report.files[0].artboards.isEmpty)
    }

    // MARK: - tree.json

    @Test("GET tree.json is byte-for-byte the tree verb's --json form")
    func treeMatchesTheVerb() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let expected = try await PenFileTransaction.read(at: bench.file, timeout: ViewerFixtures.lockBudget) { document in
            try TreeFormatter.json(TreeView.rows(of: document), revision: document.documentRevision)
        }.value

        let response = try await ViewerEndpoints.tree(
            bench.request("/files/x/tree.json", parameters: ["file": bench.fileID()])
        )
        let served = try String(decoding: body(of: response), as: UTF8.self)
        #expect(served == expected)
        #expect(response.headers["Content-Type"] == "application/json; charset=utf-8")

        let report = try JSONDecoder().decode(TreeReport.self, from: Data(served.utf8))
        #expect(!report.rows.isEmpty)
        #expect(!report.revision.isEmpty)
    }

    @Test("?node= and ?depth= narrow the tree the way the verb's flags do")
    func treeHonoursNodeAndDepth() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.tree(bench.request(
            "/files/x/tree.json",
            query: ["node": "Canvas", "depth": "0"],
            parameters: ["file": bench.fileID()]
        ))
        let report = try JSONDecoder().decode(TreeReport.self, from: body(of: response))
        #expect(report.rows.map(\.name) == ["Canvas"])
    }

    @Test("?expand= walks into instances")
    func treeExpandsInstances() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let plain = try await JSONDecoder().decode(TreeReport.self, from: body(of:
            ViewerEndpoints.tree(bench.request(
                "/files/x/tree.json", parameters: ["file": bench.fileID()]
            ))))
        let expanded = try await JSONDecoder().decode(TreeReport.self, from: body(of:
            ViewerEndpoints.tree(bench.request(
                "/files/x/tree.json", query: ["expand": ""], parameters: ["file": bench.fileID()]
            ))))
        #expect(expanded.rows.count > plain.rows.count)
    }

    @Test("A ?node= that names nothing is a 404 that says how to list the nodes")
    func treeRejectsAnUnknownNode() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        await #expect(throws: ViewerError.self) {
            try await ViewerEndpoints.tree(bench.request(
                "/files/x/tree.json",
                query: ["node": "NoSuchNode"],
                parameters: ["file": bench.fileID()]
            ))
        }
    }

    // MARK: - PNG

    @Test("GET an artboard's PNG returns an image at the artboard's size, doubled")
    func rendersAnArtboard() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.artboard(bench.request(
            "/files/x/artboards/Cnv01.png",
            parameters: ["file": bench.fileID(), "artboard": "Cnv01"]
        ))
        #expect(response.headers["Content-Type"] == "image/png")

        let data = try body(of: response)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 800)
        #expect(image.height == 600)
        #expect(response.headers["X-Woodcase-Scale"] == "2.0")
        #expect(response.headers["X-Woodcase-Width"] == "400.0")
    }

    @Test("?max caps the longest side, and the scale header says what it cost")
    func capsTheLongestSide() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.artboard(bench.request(
            "/files/x/artboards/Cnv01.png",
            query: ["max": "200"],
            parameters: ["file": bench.fileID(), "artboard": "Cnv01"]
        ))
        let source = try #require(try CGImageSourceCreateWithData(body(of: response) as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 200)
        #expect(image.height == 150)
        #expect(response.headers["X-Woodcase-Scale"] == "0.5")
    }

    @Test("An unknown artboard is a 404 that lists the ones the file has")
    func namesTheArtboardsItHas() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        do {
            _ = try await ViewerEndpoints.artboard(bench.request(
                "/files/x/artboards/Nope.png",
                parameters: ["file": bench.fileID(), "artboard": "Nope"]
            ))
            Issue.record("expected an unknownArtboard error")
        } catch let error as ViewerError {
            #expect(error.status == .notFound)
            #expect(error.message.contains("Cnv01"))
            #expect(error.remedy.contains("/files/\(bench.fileID())"))
        }
    }

    @Test("An unknown file id is a 404 that says how to list the ids")
    func namesTheRemedyForAnUnknownFile() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        do {
            _ = try await ViewerEndpoints.tree(bench.request(
                "/files/zzz/tree.json", parameters: ["file": "zzz"]
            ))
            Issue.record("expected an unknownFile error")
        } catch let error as ViewerError {
            #expect(error == ViewerError.unknownFile(id: "zzz"))
            #expect(error.remedy.contains("GET /files"))
        }
    }

    @Test("A malformed ?theme= is a 400 that shows both accepted spellings")
    func rejectsAMalformedTheme() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        do {
            _ = try await ViewerEndpoints.artboard(bench.request(
                "/files/x/artboards/Cnv01.png",
                query: ["theme": "Dark"],
                parameters: ["file": bench.fileID(), "artboard": "Cnv01"]
            ))
            Issue.record("expected a malformedTheme error")
        } catch let error as ViewerError {
            #expect(error.status == .badRequest)
            #expect(error.remedy.contains("Mode:Dark"))
        }
    }

    // MARK: - activity.json and /events

    @Test("GET activity.json returns the file's events, oldest first")
    func servesActivity() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let log = ActivityLog(home: bench.scratch)
        for name in ["First", "Second"] {
            try await PenFileTransaction.run(at: bench.file, identity: "ana", log: log, timeout: ViewerFixtures.lockBudget) { document, recorder in
                let node = try #require(document.nodes["Ttl01"])
                var common = node.common
                common.name = name
                try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Ttl01", common: common)))
            }
        }

        let response = try await ViewerEndpoints.activity(bench.request(
            "/files/x/activity.json", parameters: ["file": bench.fileID()]
        ))
        let report = try ViewerJSON.decoder.decode(ActivityReport.self, from: body(of: response))
        #expect(report.file == bench.fileID())
        #expect(report.events.count == 2)
        #expect(report.events.map(\.paths.first) == ["Canvas/First", "Canvas/Second"])
    }

    @Test("?limit caps how many events come back")
    func limitsActivity() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let log = ActivityLog(home: bench.scratch)
        for name in ["First", "Second", "Third"] {
            try await PenFileTransaction.run(at: bench.file, identity: "ana", log: log, timeout: ViewerFixtures.lockBudget) { document, recorder in
                let node = try #require(document.nodes["Ttl01"])
                var common = node.common
                common.name = name
                try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Ttl01", common: common)))
            }
        }

        let response = try await ViewerEndpoints.activity(bench.request(
            "/files/x/activity.json", query: ["limit": "1"], parameters: ["file": bench.fileID()]
        ))
        let report = try ViewerJSON.decoder.decode(ActivityReport.self, from: body(of: response))
        #expect(report.events.count == 1)
        #expect(report.events[0].paths == ["Canvas/Third"])
    }

    @Test("GET /events opens a stream rather than answering with a body")
    func opensTheStream() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.events(bench.request("/events"))
        guard case .eventStream = response.body else {
            Issue.record("expected an event stream")
            return
        }
        #expect(response.headers["Content-Type"] == "text/event-stream")
    }
}
