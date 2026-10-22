//
//  CodeGenStackTests.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Foundation
    import Testing
    @testable import Woodcase
    import WoodcasePerfFixtures

    /// How much stack code generation needs in a debug build, on trees far deeper than any
    /// design: analysis, emission and the code's layout on the page.
    ///
    /// Penumbra's Copy As and Code tab emit on a Swift task, whose thread has 512 KiB of
    /// stack. The emitters recursed one call per level and overflowed it about 11 (React)
    /// or 15 (SwiftUI) levels deep in debug (issue `g5SACU`,
    /// `project/2026-09-26-debug-stack-depth.md`). These tests measure the deepest each run
    /// reaches on a painted stack (``StackHighWater``) and hold it to a quarter of a task's
    /// (half, and no growth with depth, where instances are inlined).
    /// Every tree is built and freed off the measured thread.
    struct CodeGenStackTests {
        /// The most of a task's stack a run may use.
        private static let budget = StackHighWater.taskStackSize / 4

        /// A document of one root, `node`.
        private static func document(_ node: PenNode) -> PenDocument {
            PenDocument(version: "2.17", children: [node])
        }

        /// `template` nested `depth` times around `leaf`, each copy's id numbered, built
        /// bottom-up.
        private static func nested(_ template: String, depth: Int, around leaf: PenNode) throws -> PenNode {
            let shell = try PenParser.parse(Data(#"{"version": "2.17", "children": [\#(template)]}"#.utf8)).children[0]
            var node = leaf
            for level in stride(from: depth - 1, through: 0, by: -1) {
                node = PenNode(
                    id: "\(shell.id)\(level)", common: shell.common,
                    kind: shell.kind.replacingInlineChildren(with: [node]), extras: shell.extras
                )
            }
            return node
        }

        /// The stack a whole React and a whole SwiftUI emit of `document` use, and the code
        /// for `ids` in each language.
        private static func measureEveryEmit(_ document: PenDocument, ids: [String]) -> [(label: String, bytes: Int)] {
            let runs: [(String, () -> Int)] = [
                ("React emit", {
                    ReactEmitter.emit(
                        document: document, components: ComponentAnalyzer.analyze(document),
                        pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
                    ).files.count
                }),
                ("SwiftUI emit", {
                    (try? SwiftUIEmitter.emit(
                        document: document, components: ComponentAnalyzer.analyze(document),
                        pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
                    ).files.count) ?? -1
                }),
                ("React code", { (try? CodeGeneration.code(for: ids, in: document, language: .react).count) ?? -1 }),
                ("SwiftUI code", { (try? CodeGeneration.code(for: ids, in: document, language: .swiftUI).count) ?? -1 }),
            ]
            return runs.map { label, run in
                let measured = StackHighWater.measure(run)
                #expect(measured.result > 0, "\(label) wrote nothing")
                print("PROBE codegen stack \(label): \(measured.bytes) bytes")
                return (label, measured.bytes)
            }
        }

        @Test("A frame chain as deep as a file can hold emits inside a quarter of a task's stack")
        func frameChain() {
            let document = Self.document(DeepDocuments.chain(depth: DeepDocuments.deepestParsableDepth))

            for run in Self.measureEveryEmit(document, ids: ["D0"]) {
                #expect(run.bytes < Self.budget, "\(run.label) used \(run.bytes) bytes of stack")
            }
        }

        @Test("A tree as wide as the settings mockup and 128 deep emits inside a quarter of a task's stack")
        func mockupShaped() throws {
            let document = try Self.document(DeepDocuments.mockupShaped(wraps: 120))
            let id = try #require(document.children.first?.id)

            for run in Self.measureEveryEmit(document, ids: [id]) {
                #expect(run.bytes < Self.budget, "\(run.label) used \(run.bytes) bytes of stack")
            }
        }

        @Test("Groups with shadows, 200 deep, emit inside a quarter of a task's stack")
        func shadowedGroups() throws {
            let leaf = PenNode(id: "leaf", common: PenNodeCommon(name: "leaf"), kind: .rectangle(PenNode.RectangleData()))
            let groups = try Self.nested(
                ##"{"type": "group", "id": "g", "x": 2, "y": 3, "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000A0", "offset": {"x": 8, "y": 10}, "blur": 12}}"##,
                depth: 200, around: leaf
            )
            let board = try Self.nested(#"{"type": "frame", "id": "board", "width": 400, "height": 400}"#, depth: 1, around: groups)
            let document = Self.document(board)

            for run in Self.measureEveryEmit(document, ids: ["board0"]) {
                #expect(run.bytes < Self.budget, "\(run.label) used \(run.bytes) bytes of stack")
            }
        }

        @Test("Free-placed frames, 200 deep, emit inside a quarter of a task's stack")
        func freeFrames() throws {
            let leaf = PenNode(id: "leaf", common: PenNodeCommon(name: "leaf"), kind: .rectangle(PenNode.RectangleData()))
            let frames = try Self.nested(
                #"{"type": "frame", "id": "f", "layout": "none", "x": 1, "y": 1, "width": 100, "height": 100}"#,
                depth: 200, around: leaf
            )
            let document = Self.document(frames)

            for run in Self.measureEveryEmit(document, ids: ["f0"]) {
                #expect(run.bytes < Self.budget, "\(run.label) used \(run.bytes) bytes of stack")
            }
        }

        @Test("Nested instances filling slots emit inside half a task's stack, the same at 16 deep as at 32")
        func nestedInstances() throws {
            // Drawing an inlined instance prepares it through ``PenRefExpander``, a fixed
            // cost of about 100 KB in debug (`project/2026-09-26-debug-stack-depth.md`),
            // so this tree is held to half a task's stack, and to not growing with depth.
            var used: [Int: [(label: String, bytes: Int)]] = [:]
            for depth in [16, 32] {
                let document = try PenParser.parse(Data(DeepDocuments.nestedInstances(depth: depth, frames: 6).utf8))
                used[depth] = Self.measureEveryEmit(document, ids: ["Top", "C\(depth - 1)"])
            }

            for (shallow, deep) in zip(used[16] ?? [], used[32] ?? []) {
                #expect(deep.bytes < StackHighWater.taskStackSize / 2, "\(deep.label) used \(deep.bytes) bytes of stack")
                #expect(deep.bytes <= shallow.bytes + 4096, "\(deep.label) used \(shallow.bytes) bytes at 16 deep, \(deep.bytes) at 32")
            }
        }

        @Test("Forty turned instances, each inlined inside the next, emit inside a quarter of a task's stack")
        func inlinedInstances() throws {
            var roots = [##"{"id": "T0", "name": "T0", "type": "frame", "reusable": true, "width": 10, "height": 10, "fill": "#000000"}"##]
            for level in 1 ..< 40 {
                roots.append(
                    #"{"id": "T\#(level)", "name": "T\#(level)", "type": "frame", "reusable": true, "children": ["#
                        + #"{"id": "R\#(level)", "type": "ref", "ref": "T\#(level - 1)", "rotation": 5, "descendants": {"T0": {"opacity": 0.5}}}]}"#
                )
            }
            roots.append(#"{"id": "Page", "name": "Page", "type": "frame", "children": [{"id": "Top", "type": "ref", "ref": "T39", "rotation": 5}]}"#)
            let document = try PenParser.parse(Data(#"{"version": "2.17", "children": [\#(roots.joined(separator: ", "))]}"#.utf8))

            for run in Self.measureEveryEmit(document, ids: ["Page", "T39"]) {
                #expect(run.bytes < Self.budget, "\(run.label) used \(run.bytes) bytes of stack")
            }
        }

        @Test("A component and its state variant, 200 deep, are analyzed inside a quarter of a task's stack")
        func deepStateVariant() throws {
            let leaf = PenNode(id: "leaf", common: PenNodeCommon(name: "leaf"), kind: .rectangle(PenNode.RectangleData()))
            let inner = try Self.nested(#"{"type": "frame", "id": "b", "name": "level"}"#, depth: 199, around: leaf)
            let base = try Self.nested(
                #"{"type": "frame", "id": "chip", "name": "Chip", "reusable": true, "metadata": {"woodcase": {"role": "button"}}}"#,
                depth: 1, around: inner
            )
            var faded = leaf.common
            faded.opacity = .literal(0.5)
            let variant = try Self.nested(
                #"{"type": "frame", "id": "variant", "name": "Chip:hover"}"#, depth: 1,
                around: Self.nested(
                    #"{"type": "frame", "id": "b", "name": "level"}"#, depth: 199,
                    around: PenNode(id: "leaf", common: faded, kind: leaf.kind)
                )
            )
            let document = PenDocument(version: "2.17", children: [base, variant])

            let measured = StackHighWater.measure {
                ComponentAnalyzer.analyze(document).first?.states.first { $0.name == "hover" }?.deltas.count ?? 0
            }

            #expect(measured.result > 0)
            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
        }

        @Test("A view 1,000 deep is laid out on the page inside a quarter of a task's stack")
        func deepViewLines() {
            // Built, laid out and freed on the measured thread: freeing the tree is part of
            // what an emit pays.
            let measured = StackHighWater.measure {
                var view = SwiftUIViewCode(head: "Color.clear")
                for level in 0 ..< 1000 {
                    var stack = SwiftUIViewCode(head: "VStack", body: [view])
                    stack.modifiers = [SwiftUIViewCode.Modifier(".overlay", content: [SwiftUIViewCode(head: "Text(\"\(level)\")")])]
                    view = stack
                }
                return SwiftUIViewCode.lines(of: consume view, indent: 0).count
            }

            #expect(measured.result == 1 + 1000 * 5)
            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
        }
    }
#endif
