//
//  PenNodeDeepTreeStackTests.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Foundation
    import Testing
    @testable import Woodcase

    /// How much stack the walks that start from a node in memory need: comparing,
    /// hashing, encoding, freeing and inserting a deep tree.
    ///
    /// Each used to recurse once per level — synthesized `==` five frames a level, about
    /// 40 KB a level in a debug build — and Penumbra died of "Thread stack size
    /// exceeded" comparing a twelve-level mockup on a Swift task's 512 KiB stack
    /// (issue `a1p6vh`, `project/2026-09-26-debug-stack-depth.md`). These tests run each
    /// walk on a painted stack (``StackHighWater``) over a tree as deep as a file can
    /// hold, and hold it to a quarter of a task's stack — half for an encode, whose JSON
    /// writer is Foundation's and recursive.
    ///
    /// Every tree is built, kept and freed through a ``Holder``, on threads of their own,
    /// so only the walk under test is measured and the test thread never frees a deep
    /// tree.
    struct PenNodeDeepTreeStackTests {
        /// The most of a task's stack one walk may use.
        private static let budget = StackHighWater.taskStackSize / 4

        /// The most of a task's stack an encode to JSON may use.
        ///
        /// Our walk is flat, but `JSONEncoder` turns what it was given into JSON
        /// recursively — about 460 bytes per level of JSON nesting, two per level of the
        /// tree, so some 230 KB for a tree as deep as a file can hold. That is
        /// Foundation's, not ours to remove: an encode of the same nesting through
        /// nested containers alone, with no `PenNode` in it, uses more.
        private static let encodeBudget = StackHighWater.taskStackSize / 2

        /// A deep tree the walks must survive.
        enum Shape: String, CaseIterable, CustomTestStringConvertible {
            /// A chain of frames as deep as a file can hold.
            case chain

            /// The settings mockup's first board nested inside itself as deep as a file
            /// can hold — wide at every level.
            case mockup

            var testDescription: String {
                rawValue
            }

            /// Builds the tree. Each call builds a fresh one, sharing no storage with any
            /// other.
            func build() throws -> PenNode {
                switch self {
                case .chain: DeepDocuments.chain(depth: DeepDocuments.deepestParsableDepth)
                case .mockup: try DeepDocuments.mockupShaped()
                }
            }
        }

        @Test("Comparing two deep trees fits in a quarter of a task's stack", arguments: Shape.allCases)
        func equality(_ shape: Shape) throws {
            let holder = Holder()
            try holder.prepare { try shape.build() }
            try holder.prepare { try shape.build() }
            try holder.prepare { try DeepDocuments.renamingDeepestLastLeaf(of: shape.build(), to: "changed") }

            let measured = StackHighWater.measure {
                (equal: holder.trees[0] == holder.trees[1], changed: holder.trees[0] == holder.trees[2])
            }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result.equal)
            #expect(!measured.result.changed)
            holder.release()
        }

        @Test("Hashing a deep tree fits in a quarter of a task's stack", arguments: Shape.allCases)
        func hashing(_ shape: Shape) throws {
            let holder = Holder()
            try holder.prepare { try shape.build() }
            try holder.prepare { try shape.build() }

            let measured = StackHighWater.measure {
                holder.trees[0].hashValue == holder.trees[1].hashValue
            }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            #expect(measured.result)
            holder.release()
        }

        @Test("Encoding a deep tree fits in half a task's stack", arguments: Shape.allCases)
        func encoding(_ shape: Shape) throws {
            let holder = Holder()
            try holder.prepare { try shape.build() }

            let measured = StackHighWater.measure {
                Result { try JSONEncoder().encode(PenDocument(children: [holder.trees[0]])) }
            }

            let data = try measured.result.get()
            #expect(measured.bytes < Self.encodeBudget, "used \(measured.bytes) bytes of stack")
            try holder.prepare { try PenParser.parse(data).children[0] }
            #expect(StackHighWater.measure { holder.trees[0] == holder.trees[1] }.result)
            holder.release()
        }

        @Test("Freeing a deep tree fits in a quarter of a task's stack", arguments: Shape.allCases)
        func freeing(_ shape: Shape) throws {
            let holder = Holder()
            try holder.prepare { try shape.build() }

            let measured = StackHighWater.measure { holder.drop() }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
        }

        @Test("Freeing a chain five thousand frames deep fits in a quarter of a task's stack")
        func freeingFarDeeperThanAFile() throws {
            let holder = Holder()
            try holder.prepare { DeepDocuments.chain(depth: 5000) }

            let measured = StackHighWater.measure { holder.drop() }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
        }

        @Test("Inserting a deep subtree into an editable document fits in a quarter of a task's stack", arguments: Shape.allCases)
        func inserting(_ shape: Shape) throws {
            let holder = Holder()
            try holder.prepare { try shape.build() }
            let document = EditableDocument(from: PenDocument(children: []))

            let measured = StackHighWater.measure {
                Result { try document.apply(.insertNode(EditOperation.InsertNode(node: holder.trees[0]))) }
            }

            try measured.result.get()
            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            #expect(document.rootOrder == [holder.trees[0].id])
            holder.release()
        }

        // MARK: - Helpers

        /// The trees a test compares, made and freed off the test thread.
        private final class Holder {
            /// The trees, in the order they were made.
            private(set) var trees: [PenNode] = []

            /// Builds a tree on a thread with room to, and keeps it.
            func prepare(_ build: @escaping () throws -> PenNode) throws {
                let tree = try StackHighWater.measure { Result { try build() } }.result.get()
                trees.append(tree)
            }

            /// Frees every tree, on a thread with room to.
            func release() {
                _ = StackHighWater.measure { self.drop() }
            }

            /// Frees every tree, on the calling thread.
            func drop() {
                trees = []
            }
        }
    }
#endif
