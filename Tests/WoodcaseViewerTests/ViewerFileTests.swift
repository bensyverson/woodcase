//
//  ViewerFileTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

struct ViewerFileTests {
    @Test("A file's id is a short hex hash of its canonical path")
    func hashesTheCanonicalPath() {
        let file = ViewerFile(url: URL(fileURLWithPath: "/tmp/demo.pen"))
        // Hoisted out of the macro: inside `#expect`, `allSatisfy(\.isHexDigit)`
        // expands into a context where the rethrows call needs a `try`.
        let isHexadecimal = file.id.allSatisfy(\.isHexDigit)
        #expect(file.id.count == 12)
        #expect(isHexadecimal)
    }

    @Test("The same file spelled two ways gets one id, so a URL survives a restart")
    func idIsStableAcrossSpellings() throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)

        let direct = ViewerFile(url: file)
        let indirect = ViewerFile(url: file.deletingLastPathComponent()
            .appendingPathComponent("./batch.pen"))
        #expect(direct.id == indirect.id)
        #expect(direct.path == ActivityEvent.canonicalPath(for: file))
    }

    @Test("Different files get different ids")
    func idsDiffer() {
        let one = ViewerFile(url: URL(fileURLWithPath: "/tmp/one.pen"))
        let two = ViewerFile(url: URL(fileURLWithPath: "/tmp/two.pen"))
        #expect(one.id != two.id)
    }

    @Test("The name is the file name without its extension")
    func namesTheFile() {
        #expect(ViewerFile(url: URL(fileURLWithPath: "/tmp/demo.pen")).name == "demo")
    }

    @Test("The index finds a file by id and reports the files in the order given")
    func indexesByID() async {
        let first = URL(fileURLWithPath: "/tmp/one.pen")
        let second = URL(fileURLWithPath: "/tmp/two.pen")
        let index = ViewerFileIndex(files: [first, second])

        let all = await index.files
        #expect(all.map(\.name) == ["one", "two"])
        let found = await index.file(id: ViewerFile(url: second).id)
        #expect(found?.name == "two")
        #expect(await index.file(id: "deadbeef") == nil)
    }

    @Test("A file named twice is indexed once")
    func deduplicates() async {
        let index = ViewerFileIndex(files: [
            URL(fileURLWithPath: "/tmp/one.pen"),
            URL(fileURLWithPath: "/tmp/./one.pen"),
        ])
        #expect(await index.files.count == 1)
    }

    @Test("With no files given, the index adopts every .pen file the activity log names")
    func discoversFromTheLog() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let log = ActivityLog(home: scratch)
        try await log.append([ActivityEvent(
            time: Date(), identity: "tester", file: file, op: .set, revision: "r1"
        )])

        let index = ViewerFileIndex(files: [])
        await index.adoptFilesFromLogs([log])
        #expect(await index.files.map(\.name) == ["batch"])
    }

    @Test("The log's own files are ignored when explicit files were given")
    func explicitFilesWin() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let other = try ViewerFixtures.copy("addressing.pen", into: scratch)
        let log = ActivityLog(home: scratch)
        try await log.append([ActivityEvent(
            time: Date(), identity: "tester", file: other, op: .set, revision: "r1"
        )])

        let index = ViewerFileIndex(files: [file])
        await index.adoptFilesFromLogs([log])
        #expect(await index.files.map(\.name) == ["batch"])
    }
}
