//
//  TreePipelineStackTests.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Foundation
    import Testing
    @testable import Woodcase

    /// How much stack each stage of the settled-tree read needs in a debug build.
    ///
    /// `woodcase tree` parses, expands, resolves, lays out and lists a document inside a
    /// Swift task, whose thread has 512 KiB of stack. Every stage used to walk the tree
    /// recursively with kilobytes of debug frame per level, so a frame tree about thirty
    /// deep, or sixteen nested instances, killed the process with SIGBUS
    /// (`project/2026-09-26-debug-stack-depth.md`). These tests measure each stage on a
    /// painted stack (``StackHighWater``) at the depths the verb must survive, and hold
    /// each walk to a quarter of a task's stack; the whole read gets half.
    ///
    /// Freeing a tree is the one step that still recurses: the compiler writes a value's
    /// destruction, one call per level — about 770 bytes a level in a debug build — and
    /// there is no hook to stop it. Expanding an editable document frees the tree it
    /// materialized, settling frees the expanded tree, and the whole read frees
    /// everything; at these depths that free, not any walk, is each one's deepest point,
    /// so those three get half a task's stack. JSON nesting bounds the depth: Foundation refuses input nested past
    /// 512 arrays and objects, so no file parses to a frame tree deeper than 255.
    ///
    /// Inputs are built and outputs freed on threads of their own, so only the stage
    /// under test is measured and the test thread never holds a deep tree.
    struct TreePipelineStackTests {
        /// The most of a task's stack one stage may use.
        private static let stageBudget = StackHighWater.taskStackSize / 4

        /// The most of a task's stack the whole read may use.
        private static let readBudget = StackHighWater.taskStackSize / 2

        /// The most of a task's stack a stage that frees a deep tree may use.
        private static let freeBudget = StackHighWater.taskStackSize / 2

        /// A generated document the read must survive.
        enum Shape: String, CaseIterable, CustomTestStringConvertible {
            /// A plain frame tree two hundred levels deep.
            case frames

            /// Thirty-two components, each placing the one before it behind one frame.
            case instances

            var testDescription: String {
                rawValue
            }

            /// The document's JSON.
            var json: String {
                switch self {
                case .frames: DeepDocuments.frameTree(depth: 200)
                case .instances: DeepDocuments.nestedInstances(depth: 32, frames: 1)
                }
            }

            /// The subtree the listing starts from.
            var root: String? {
                self == .instances ? "Top" : nil
            }

            /// The id that ends the deepest row.
            var deepestSuffix: String {
                self == .instances ? "Leaf" : "D199"
            }
        }

        @Test("Parsing a deep document fits in a quarter of a task's stack", arguments: Shape.allCases)
        func parsing(_ shape: Shape) throws {
            let data = Data(shape.json.utf8)
            let holder = Holder()

            let measured = StackHighWater.measure {
                Result { try holder.keep(PenParser.parse(data)) }
            }

            let parsed = try measured.result.get()
            #expect(measured.bytes < Self.stageBudget, "used \(measured.bytes) bytes of stack")
            #expect(DeepDocuments.depthOfDeepestRoot(in: parsed) == (shape == .frames ? 200 : 3))
            holder.release()
        }

        @Test("Expanding a deep editable document fits in half a task's stack", arguments: Shape.allCases)
        func expanding(_ shape: Shape) throws {
            let holder = Holder()
            let document = try holder.prepare { try EditableDocument(from: PenParser.parse(Data(shape.json.utf8))) }

            let measured = StackHighWater.measure {
                DeepDocuments.depthOfDeepestRoot(in: holder.keep(document.expanded(for: .canvas)))
            }

            #expect(measured.bytes < Self.freeBudget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result == (shape == .frames ? 200 : 31 * 2 + 3))
            holder.release()
        }

        @Test("Resolving variables in a deep document fits in a quarter of a task's stack", arguments: Shape.allCases)
        func resolving(_ shape: Shape) throws {
            let holder = Holder()
            let expanded = try holder.prepare { try EditableDocument(from: PenParser.parse(Data(shape.json.utf8))).expanded(for: .canvas) }

            let measured = StackHighWater.measure {
                DeepDocuments.depthOfDeepestRoot(in: holder.keep(PenVariableResolver.resolve(expanded, theme: [:])))
            }

            #expect(measured.bytes < Self.stageBudget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result == DeepDocuments.depthOfDeepestRoot(in: expanded))
            holder.release()
        }

        @Test("Collecting a deep document's font families fits in a quarter of a task's stack", arguments: Shape.allCases)
        func collectingFonts(_ shape: Shape) throws {
            let holder = Holder()
            let resolved = try holder.prepare {
                try PenVariableResolver.resolve(
                    EditableDocument(from: PenParser.parse(Data(shape.json.utf8))).expanded(for: .canvas),
                    theme: [:]
                )
            }

            let measured = StackHighWater.measure {
                GoogleFontResolver.collectFontFamilies(from: resolved)
            }

            #expect(measured.bytes < Self.stageBudget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result.isEmpty)
            holder.release()
        }

        @Test("Laying out a deep document fits in a quarter of a task's stack", arguments: Shape.allCases)
        func layingOut(_ shape: Shape) throws {
            let holder = Holder()
            let resolved = try holder.prepare {
                try PenVariableResolver.resolve(
                    EditableDocument(from: PenParser.parse(Data(shape.json.utf8))).expanded(for: .canvas),
                    theme: [:]
                )
            }

            let measured = StackHighWater.measure {
                PenLayoutEngine.layout(resolved, textMeasurer: Self.noText).count
            }

            #expect(measured.bytes < Self.stageBudget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result > (shape == .frames ? 199 : 90))
            holder.release()
        }

        @Test("Settling a deep document fits in half a task's stack", arguments: Shape.allCases)
        func settling(_ shape: Shape) throws {
            let holder = Holder()
            let document = try holder.prepare { try EditableDocument(from: PenParser.parse(Data(shape.json.utf8))) }

            let measured = StackHighWater.measure {
                holder.keep(SettledTree(document: document, theme: [:], textMeasurer: Self.noText)).rects.count
            }

            #expect(measured.bytes < Self.freeBudget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result > (shape == .frames ? 199 : 90))
            holder.release()
        }

        @Test("Listing a settled deep document fits in a quarter of a task's stack", arguments: Shape.allCases)
        func listing(_ shape: Shape) throws {
            let holder = Holder()
            let document = try holder.prepare { try EditableDocument(from: PenParser.parse(Data(shape.json.utf8))) }
            let settled = try holder.prepare { SettledTree(document: document, theme: [:], textMeasurer: Self.noText) }

            let measured = StackHighWater.measure {
                Result {
                    try TreeView.rows(of: document, settled: settled, root: shape.root, expandInstances: true)
                }
            }

            let rows = try measured.result.get()
            #expect(measured.bytes < Self.stageBudget, "used \(measured.bytes) bytes of stack")
            #expect(rows.contains { $0.id.hasSuffix(shape.deepestSuffix) })
            holder.release()
        }

        @Test("Flattening a deep document into the editable store fits in a quarter of a task's stack", arguments: Shape.allCases)
        func flattening(_ shape: Shape) throws {
            let holder = Holder()
            let parsed = try holder.prepare { try PenParser.parse(Data(shape.json.utf8)) }

            let measured = StackHighWater.measure {
                holder.keep(EditableDocument(from: parsed)).rootOrder.count
            }

            #expect(measured.bytes < Self.stageBudget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result > 0)
            holder.release()
        }

        @Test("The whole tree read of a deep document fits in half a task's stack", arguments: Shape.allCases)
        func wholeRead(_ shape: Shape) throws {
            let data = Data(shape.json.utf8)

            let measured = StackHighWater.measure {
                Result { () throws -> Bool in
                    let document = try EditableDocument(from: PenParser.parse(data))
                    let rows = try TreeView.rows(of: document, root: shape.root, expandInstances: true)
                    return rows.contains { $0.id.hasSuffix(shape.deepestSuffix) }
                }
            }

            #expect(measured.bytes < Self.readBudget, "used \(measured.bytes) bytes of stack")
            #expect(try measured.result.get())
        }

        // MARK: - Helpers

        /// A text measurer that needs no fonts; the documents hold no text.
        private static let noText: TextMeasurer = { _, _, _, _, _, _, _, _ in (0, 0) }

        /// Everything a test builds or keeps, made and freed off the test thread.
        private final class Holder {
            /// What the test made, kept so it is not freed where it was made.
            private var kept: [Any] = []

            /// Builds a stage's input on a thread with room to, and keeps it.
            func prepare<T>(_ build: @escaping () throws -> T) throws -> T {
                let value = try StackHighWater.measure { Result { try build() } }.result.get()
                kept.append(value)
                return value
            }

            /// Keeps a value alive past the measured work, and returns it.
            func keep<T>(_ value: T) -> T {
                kept.append(value)
                return value
            }

            /// Frees everything the holder keeps, on a thread with room to.
            func release() {
                _ = StackHighWater.measure { self.drop() }
            }

            /// Frees everything the holder keeps, on the calling thread.
            func drop() {
                kept = []
            }
        }
    }
#endif
