//
//  JsRowTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// The row a `js` script filters is the row a `find` predicate filters.
///
/// Driven through the built binary, because the fact under test is what a caller who
/// read `woodcase find --help` types next: `r.props['kind.content']` over `doc.tree`.
/// When that read `undefined` the script filtered nothing, wrote nothing and exited 0 —
/// the silent wrong answer the row `Proxy` exists to prevent, on the write side.
@Suite("woodcase js rows")
struct JsRowTests {
    /// Writes a script beside the fixture and answers with its path.
    private func script(_ body: String, named name: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url.path
    }

    @Test("a filter on r.props reads the column doc.tree's props option asked for")
    func propsFiltersTheRows() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            """
            doc.tree(null, { props: ['kind.content'] })
              .filter(r => r.props['kind.content'] === 'Canvas')
              .map(r => r.id)
            """,
            named: "columns.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 0)
        #expect(run.stdout.contains(#"result  ["Ttl01"]"#))
    }

    @Test("r.props without the option exits 1 and says which option would fill it")
    func propsWithoutTheOptionRefuses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            "doc.tree().filter(r => r.props['kind.fontSize'] < 12)",
            named: "no-columns.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 1)
        #expect(run.stderr.contains("props: ['kind.fontSize']"))
        #expect(run.stderr.contains("is byte for byte what it was."))
    }

    @Test("a property read straight off the row exits 1 and lists the row's members")
    func anUnknownMemberRefuses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            "doc.tree().filter(r => r.fontSize < 12)",
            named: "member.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 1)
        #expect(run.stderr.contains("a row has no fontSize"))
        #expect(run.stderr.contains("absRect"))
    }
}
