//
//  PenRefExpanderStackTests.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Foundation
    import Testing
    @testable import Woodcase

    /// How much stack ``PenRefExpander`` needs in a debug build.
    ///
    /// `EditableDocument.expanded` runs inside Swift tasks, whose threads have 512 KiB of
    /// stack, and a debug build gives every value temporary its own slot: the expander
    /// used to reserve kilobytes per level of the tree and overflowed four nested
    /// instances deep — `woodcase tree` died of SIGBUS with no output
    /// (`project/2026-09-26-debug-stack-depth.md`). These tests measure the deepest the
    /// expansion reaches on a painted stack (``StackHighWater``) and hold it to a budget
    /// well inside a task's, leaving the rest to whoever called it.
    ///
    /// Every deep tree is built and freed on a thread of its own: freeing one recurses as
    /// deep as the tree — about 800 bytes a level in a debug build — and a test thread
    /// is itself a task's. Only the expansion is measured.
    struct PenRefExpanderStackTests {
        /// The most of a task's stack an expansion may use, freeing its result included.
        private static let budget = StackHighWater.taskStackSize / 4

        @Test("Sixteen nested instances, each behind six frames, expand inside a quarter of a task's stack")
        func deepInstanceNesting() throws {
            let document = try Holder(DeepDocuments.nestedInstances(depth: 16, frames: 6))

            let measured = StackHighWater.measure {
                let expanded = document.keep(PenRefExpander.expand(document.parsed, for: .canvas))
                let top = expanded.children.first { $0.id == "Top/C15" }
                return (
                    depth: top.map(DeepDocuments.depth(of:)),
                    name: top.flatMap { DeepDocuments.node(endingIn: "Inj15", in: $0) }?.common.name
                )
            }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result.depth == 15 * 7 + 3, "depth \(String(describing: measured.result.depth))")
            #expect(measured.result.name == "patched", "name \(String(describing: measured.result.name))")
            document.release()
        }

        @Test("A frame tree two hundred levels deep expands inside a quarter of a task's stack")
        func deepFrameTree() throws {
            let document = try Holder(DeepDocuments.frameTree(depth: 200))

            let measured = StackHighWater.measure {
                document.keep(PenRefExpander.expand(document.parsed)).children.first.map(DeepDocuments.depth(of:))
            }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result == 200)
            document.release()
        }

        /// A parsed document, and what was made from it, that never touch the test
        /// thread's stack: parsed on a thread of its own, and freed by ``release()`` on
        /// another.
        private final class Holder {
            /// The document as parsed.
            private(set) var parsed: PenDocument

            /// Whatever the test made from it, kept so it is not freed where it was made.
            private var kept: [PenDocument] = []

            init(_ json: String) throws {
                parsed = try StackHighWater.measure {
                    Result { try PenParser.parse(Data(json.utf8)) }
                }.result.get()
            }

            /// Frees everything the holder keeps, on a thread with room to.
            func release() {
                _ = StackHighWater.measure {
                    self.parsed = PenDocument(children: [])
                    self.kept = []
                }
            }

            /// Keeps a document alive past the measured work, and returns it.
            func keep(_ document: PenDocument) -> PenDocument {
                kept.append(document)
                return document
            }
        }
    }
#endif
