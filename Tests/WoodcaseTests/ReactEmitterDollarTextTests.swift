//
//  ReactEmitterDollarTextTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A text whose copy starts with `$` but names no variable of the document (`$9`, a
/// price) is that copy, as the resolver and the SwiftUI emitter read it (issue `7aBGl9`).
struct ReactEmitterDollarTextTests {
    /// The `.tsx` the page of one text of `content` emits, in a document with a string
    /// variable `headline`.
    private static func page(content: String) throws -> String {
        let document = try PenParser.parse(Data("""
        {"version": "2.17",
         "variables": {"headline": {"type": "string", "value": "Hello"}},
         "children": [
            {"id": "p", "name": "Price", "type": "frame", "children": [
                {"id": "t", "name": "Amount", "type": "text", "content": "\(content)", "fill": "#000000"}
            ]}
         ]}
        """.utf8))
        let result = ReactEmitter.emit(
            document: document,
            components: [],
            pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        )
        return try #require(result.files.first { $0.path == "pages/Price.tsx" }).content
    }

    @Test("A $9 no variable has is written as $9")
    func dollarLiteral() throws {
        let page = try Self.page(content: "$9")

        #expect(page.contains("  $9\n"))
        #expect(!page.contains("&nbsp;"))
        #expect(!page.contains("minHeight"))
    }

    @Test("A $name of letters no variable has is written as itself")
    func dollarWordLiteral() throws {
        let page = try Self.page(content: "$a")

        #expect(page.contains("$a"))
        #expect(!page.contains("&nbsp;"))
    }
}
