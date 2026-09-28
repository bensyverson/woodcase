//
//  SwiftUIEmitterTypeNameTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which names a page or component may not take in the emitted module: every type the
/// support templates declare, read from the templates themselves.
struct SwiftUIEmitterTypeNameTests {
    @Test("A page named like any type a support template declares is suffixed Page")
    func supportTypesAreShadowed() throws {
        let declared = try Self.declaredTypes()
        // Guards the parse: the templates declare these, and the check below means nothing without them.
        #expect(declared.isSuperset(of: ["PenShadowStyle", "PenLineBox", "PenGradient", "PenFontFace", "PenSideStroke"]))
        // A page's name is its frame's words capitalized and joined: "Pen Line Box" is PenLineBox.
        let frames = declared.sorted().enumerated().map { index, name in
            let words = name.replacing(/([a-z0-9])([A-Z])/) { "\($0.1) \($0.2)" }
            return ##"{"type": "frame", "id": "f\##(index)", "name": "\##(words)", "width": 10, "height": 10}"##
        }
        let json = ##"{"version": "2.17", "children": [\##(frames.joined(separator: ", "))]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        )
        let paths = Set(result.files.map(\.path))
        for name in declared {
            #expect(paths.contains { $0.hasSuffix("Pages/\(name)Page.swift") }, "a page named \(name) would shadow the support type")
        }
    }

    /// The type names the support templates declare at the top level, where a page's
    /// type would clash with them: every unindented `struct`, `enum`, `class`, `actor`,
    /// `protocol` and `typealias`, access and `final` modifiers allowed.
    private static func declaredTypes() throws -> Set<String> {
        let keywords: Set<Substring> = ["struct", "enum", "class", "actor", "protocol", "typealias"]
        let modifiers: Set<Substring> = ["public", "internal", "fileprivate", "private", "final"]
        var names: Set<String> = []
        for template in try SwiftUIEmitter.supportTemplates().values {
            for line in template.split(separator: "\n") where line.first?.isLetter == true {
                let words = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).drop(while: modifiers.contains)
                guard let keyword = words.first, keywords.contains(keyword), let name = words.dropFirst().first else { continue }
                names.insert(String(name))
            }
        }
        return names
    }
}
