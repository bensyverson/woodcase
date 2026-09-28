//
//  SwiftUIVocabularyMatchingTests.swift
//  WoodcaseTests
//

import Testing

/// When a listed path covers a use the scanner found: a call must fit one listed label
/// list, defaulted arguments left out and trailing closures taking the parameters after it.
struct SwiftUIVocabularyMatchingTests {
    /// Whether `list` covers every use in `source`.
    private func covers(_ list: String, _ source: String, byNameOnly: Bool = false) throws -> Bool {
        let vocabulary = try SwiftUIVocabulary(list)
        let uses = SwiftUIAPIScanner.uses(in: SwiftUIAPIScanner.code(source))
        try #require(!uses.isEmpty)
        return uses.allSatisfy { vocabulary.covers($0, byNameOnly: byNameOnly) }
    }

    @Test("A call fits when its labels are an in-order subset of the listed ones")
    func labelSubset() throws {
        #expect(try covers("View.shadow(color:radius:x:y:)", "v.shadow(color: c, radius: 2)"))
        #expect(try covers("View.shadow(color:radius:x:y:)", "v.shadow(radius: 2, color: c)") == false)
        #expect(try covers("View.shadow(color:radius:x:y:)", "v.shadow(opacity: 2)") == false)
        #expect(try covers("View.shadow(color:radius:x:y:)", "v.shadow(opacity: 2)", byNameOnly: true))
    }

    @Test("A trailing closure needs a listed parameter after the labelled ones")
    func trailingClosure() throws {
        #expect(try covers("View.background(alignment:content:)\nAlignment.top", "v.background(alignment: .top) { x }"))
        #expect(try covers("View.padding(_:)", "v.padding(4) { x }") == false)
    }

    @Test("A type is covered by any path that names it; its call by an initializer or a function")
    func typesAndInitializers() throws {
        #expect(try covers("ButtonStyle.Configuration", "let c: Configuration"))
        #expect(try covers("Path.init()", "Path()"))
        #expect(try covers("Path.init()", "Path(rect)") == false)
        #expect(try covers("CTFontGetAscent(_:)", "CTFontGetAscent(font)"))
        #expect(try covers("MeshGradient.BezierPoint.init(position:)", "MeshGradient.BezierPoint(position: p)"))
        #expect(try covers("MeshGradient.BezierPoint.init(position:)", "MeshGradient.BezierPoint(color: c)") == false)
        #expect(try covers("Preview(_:body:)", "#Preview(\"A\") { x }"))
    }

    @Test("A member without a call is covered by its name")
    func members() throws {
        #expect(try covers("Alignment.topLeading", "v.frame(alignment: .topLeading)") == false)
        #expect(try covers("Alignment.topLeading\nView.frame(width:height:alignment:)", "v.frame(alignment: .topLeading)"))
        #expect(try covers("Alignment.topLeading", "let a = .topLeading"))
        #expect(try covers("kCTFontNameAttribute", "let a = kCTFontNameAttribute"))
    }
}
