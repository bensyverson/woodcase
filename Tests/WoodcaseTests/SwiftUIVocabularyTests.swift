//
//  SwiftUIVocabularyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Keeps `Fixtures/swiftui-vocabulary.txt` — the list `scripts/swiftui-api audit` checks
/// against the SDK — honest: every SDK API the emitted package calls must be on it.
///
/// Three sources are read: the support templates, every SwiftUI golden, and the code
/// fragments in the emitter's own string literals (by name only, since their arguments are
/// interpolated). A name the emitted code declares itself, or one on
/// ``SwiftUIVocabularyExemptions``, is not an SDK use. Runs wherever the goldens do: it
/// reads text, and needs neither SwiftUI nor the SDK corpus.
struct SwiftUIVocabularyTests {
    private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private static let vocabulary: SwiftUIVocabulary = {
        let url = SwiftUIFixtures.directory.appendingPathComponent("swiftui-vocabulary.txt")
        return (try? SwiftUIVocabulary(String(contentsOf: url, encoding: .utf8))) ?? SwiftUIVocabulary()
    }()

    /// The emitted sources: every support template and every `.swift.golden` under
    /// `golden/swiftui/`, by name.
    private static let emitted: [String: String] = {
        var sources = SwiftUIEmitter.supportTemplates
        let root = SwiftUIFixtures.directory.appendingPathComponent("golden/swiftui")
        let paths = FileManager.default.subpaths(atPath: root.path) ?? []
        for path in paths where path.hasSuffix(".swift.golden") {
            sources[path] = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        return sources
    }()

    /// What the emitted code declares for itself, across every emitted source.
    private static let declared = SwiftUIAPIScanner.Declarations(
        emitted.values.map { SwiftUIAPIScanner.code($0) }.joined(separator: "\n")
    )

    /// `use` is neither on the list, nor the emitted code's own, nor exempt.
    private static func isUnlisted(_ use: SwiftUIAPIUse, byNameOnly: Bool = false) -> Bool {
        !declared.declares(use) && !vocabulary.covers(use, byNameOnly: byNameOnly)
            && !SwiftUIVocabularyExemptions.list.covers(use, byNameOnly: byNameOnly)
    }

    @Test("The list parses: a path per line, known annotations, no duplicates")
    func listParses() throws {
        let url = SwiftUIFixtures.directory.appendingPathComponent("swiftui-vocabulary.txt")
        let list = try SwiftUIVocabulary(String(contentsOf: url, encoding: .utf8))
        #expect(list.entries.count > 200)
        #expect(Set(list.entries.map(\.path)).count == list.entries.count, "a path is listed twice")
        #expect(list.entries.contains { $0.gate != nil }, "the lineHeight branch is gated")
        #expect(throws: SwiftUIVocabulary.ParseError.self) { try SwiftUIVocabulary("View.body @sometimes") }
    }

    @Test("Every SDK API the templates and goldens call is on the list", arguments: emitted.keys.sorted())
    func emittedCodeIsListed(source: String) throws {
        let code = try SwiftUIAPIScanner.code(#require(Self.emitted[source]))
        let unlisted = Set(SwiftUIAPIScanner.uses(in: code).filter { Self.isUnlisted($0) }.map(\.description))
        #expect(unlisted.isEmpty, "not on swiftui-vocabulary.txt: \(unlisted.sorted().joined(separator: ", "))")
    }

    @Test("Every SDK name in the emitter's own code fragments is on the list")
    func emitterFragmentsAreListed() throws {
        let emitter = Self.testsDirectory.appendingPathComponent("../../Sources/Woodcase/CodeGen/SwiftUI").standardized
        let files = try FileManager.default.contentsOfDirectory(atPath: emitter.path)
            // The manifest writes PackageDescription, which is SwiftPM's, not the SDK's.
            .filter { $0.hasSuffix(".swift") && $0 != "SwiftUIEmitter+Package.swift" }
        #expect(files.count > 20)
        var unlisted: Set<String> = []
        for file in files {
            let source = try String(contentsOf: emitter.appendingPathComponent(file), encoding: .utf8)
            for fragment in SwiftUIAPIScanner.literals(in: source) {
                let uses = SwiftUIAPIScanner.uses(in: SwiftUIAPIScanner.code(fragment), callsOnly: true)
                unlisted.formUnion(uses.filter { Self.isUnlisted($0, byNameOnly: true) }.map { "\($0) in \(file)" })
            }
        }
        #expect(unlisted.isEmpty, "not on swiftui-vocabulary.txt: \(unlisted.sorted().joined(separator: ", "))")
    }

    @Test("Every member an emitter site spells from an enum is on the list")
    func enumeratedMembersAreListed() {
        // SwiftUIAlignment's axes are not CaseIterable; these are all their cases.
        let verticals: [SwiftUIAlignment.Vertical] = [.top, .center, .bottom]
        let horizontals: [SwiftUIAlignment.Horizontal] = [.leading, .center, .trailing]
        var members: [String] = []
        for vertical in verticals {
            for horizontal in horizontals {
                members.append("Alignment" + SwiftUIAlignment(horizontal: horizontal, vertical: vertical).code)
            }
            members.append("VerticalAlignment.\(vertical.rawValue)")
        }
        members += horizontals.map { "HorizontalAlignment.\($0.rawValue)" }
        for x in [0.0, 0.5, 1] {
            for y in [0.0, 0.5, 1] {
                members.append("UnitPoint" + SwiftUILiteral.unitPoint(NormalizedPoint(x: x, y: y)))
            }
        }
        members += Self.blendModes.compactMap(SwiftUIBlendMode.name(for:)).map { "BlendMode.\($0)" }
        members += PenStrokeCap.allCases.filter { $0 != .butt }.map { "CGLineCap.\($0.rawValue)" }
        members += PenStrokeJoin.allCases.filter { $0 != .miter }.map { "CGLineJoin.\($0.rawValue)" }
        let listed = Set(Self.vocabulary.entries.map(\.path))
        #expect(members.count == 9 + 3 + 3 + 9 + 18 + 2 + 2)
        #expect(members.filter { !listed.contains($0) } == [])
    }

    /// Every blend mode Pen names; `PenBlendMode` is not `CaseIterable`, having an
    /// `unknown` case.
    private static let blendModes: [PenBlendMode] = [
        .normal, .darken, .multiply, .linearBurn, .colorBurn, .light, .screen, .linearDodge, .colorDodge,
        .overlay, .softLight, .hardLight, .difference, .exclusion, .hue, .saturation, .color, .luminosity,
    ]
}
