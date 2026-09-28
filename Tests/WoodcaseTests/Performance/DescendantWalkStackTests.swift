//
//  DescendantWalkStackTests.swift
//  WoodcaseTests
//

#if canImport(Darwin)

    import Foundation
    import Testing
    @testable import Woodcase

    /// How much stack the descendant-key and injected-node walks need in a debug build.
    ///
    /// `appendDescendantKeys`/`appendInjectedKeys` (`EditableDocument+DescendantKeys.swift`)
    /// and `collectInjected` (`EditableDocument+Injected.swift`) used to recurse one Swift
    /// call per level: a chain of components each placing the next, or a component's own
    /// body nested down to a slot, would eventually overflow a task's 512 KiB stack in a
    /// debug build (`project/2026-09-26-debug-stack-depth.md`). These tests measure the
    /// deepest either walk reaches on a painted stack (``StackHighWater``) and hold it to a
    /// budget well inside a task's — the same budget ``PenRefExpanderStackTests`` uses for
    /// the same class of walk.
    ///
    /// Neither fixture is built from `.pen` JSON text nested to the depth under test: Apple's
    /// JSON parser refuses input nested past roughly 255 levels
    /// (`TreeDeepNestingTests.frameTreeDepth`'s own comment), far short of a depth that
    /// reliably exercises a recursive walk's stack cost. The component chain sidesteps this
    /// because it is *wide*, not deep — every component is two nodes at most, chained by a
    /// `ref` string, so parsing it is ordinary. The nested-slot fixture is built as `PenNode`
    /// values directly, with no JSON in between — but a genuinely deep single node value is
    /// still expensive to let go of: `EditableDocument.init(from:)`'s own `document`
    /// parameter holds the *original*, unflattened tree until `init` returns, and freeing it
    /// then recurses one call per level exactly the way ``PenRefExpanderStackTests``
    /// documents (`project/2026-09-26-debug-stack-depth.md`'s "still recurses" list). That
    /// is a separate, already-known, out-of-scope cost — not `collectInjected`'s — so
    /// ``DeepSlotDocumentHolder`` builds and frees the document on ``StackHighWater``'s own
    /// generously-stacked thread, the same way ``PenRefExpanderStackTests/Holder`` does, and
    /// only the walk itself is measured against the budget.
    struct DescendantWalkStackTests {
        /// The most of a task's stack either walk may use.
        private static let budget = StackHighWater.taskStackSize / 4

        /// Reusable components chained end to end, each placing the next by `ref`. Far
        /// past where the old recursive `appendDescendantKeys` used one Swift call per
        /// level; kept in the low thousands because each level's `effectiveRefData` call
        /// costs the whole chain so far, making the walk itself O(depth²).
        private static let componentChainDepth = 1500

        /// Frames nested inside a component's own body before its slot, far past where the
        /// old recursive `collectInjected` used one Swift call per level, and far past the
        /// ~255-level ceiling a `.pen` file could even parse.
        private static let slotNestingDepth = 5000

        @Test("A chain of thousands of components each placing the next is walked for descendant keys, not recursed")
        func chainedComponentsDoNotRecurse() throws {
            let json = Self.chainedComponentsDocument(count: Self.componentChainDepth)
            let parsed = try PenParser.parse(Data(json.utf8))

            let measured = StackHighWater.measure {
                let document = EditableDocument(from: parsed)
                return document.overridableDescendantKeys(ofInstance: "Inst0").count
            }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            // One key for each component's own root, one for each `ref` step between
            // them, and no root for the walk to have skipped or doubled.
            #expect(measured.result == 2 * Self.componentChainDepth - 1)
        }

        @Test("A slot nested thousands of frames inside a component's own body is found by the injected-node walk, not recursed onto")
        func deeplyNestedSlotDoesNotRecurse() throws {
            let holder = DeepSlotDocumentHolder(depth: Self.slotNestingDepth)
            let document = try #require(holder.document, "the document did not survive its own construction")

            let measured = StackHighWater.measure {
                document.injectedNodes(insideInstances: ["Inst0"]).count
            }

            #expect(measured.bytes < Self.budget, "used \(measured.bytes) bytes of stack")
            // The one leaf the instance injected into the slot at the bottom of the chain.
            #expect(measured.result == 1)
            holder.release()
        }

        // MARK: - Fixtures

        /// `count` reusable frame components, `Cmp0` through `Cmp<count-1>`, each but the
        /// last holding one `ref` child that places the next; the last is a leaf. One
        /// instance, `Inst0`, places `Cmp0`. Every component is at most two nodes deep, so
        /// parsing this is ordinary however large `count` is — the depth under test is in
        /// how many components the walk steps through, not in how deeply any one JSON
        /// object nests.
        private static func chainedComponentsDocument(count: Int) -> String {
            var parts: [String] = []
            for index in 0 ..< count {
                if index < count - 1 {
                    parts.append(
                        #"{"id": "Cmp\#(index)", "type": "frame", "reusable": true, "#
                            + #""children": [{"id": "Rf\#(index)", "type": "ref", "ref": "Cmp\#(index + 1)"}]}"#
                    )
                } else {
                    parts.append(#"{"id": "Cmp\#(index)", "type": "frame", "reusable": true}"#)
                }
            }
            parts.append(#"{"id": "Inst0", "type": "ref", "ref": "Cmp0"}"#)
            return #"{"version": "2.17", "children": [\#(parts.joined(separator: ", "))]}"#
        }

        /// One reusable component, `Card0`, whose body is `depth` plain frames nested
        /// inside one another before reaching its slot frame; one instance, `Inst0`, fills
        /// that slot with a single leaf rectangle, `Leaf0`. Built as `PenNode` values
        /// directly — the only JSON round trip is encoding and decoding the *leaf* alone,
        /// which is one node deep regardless of `depth`.
        fileprivate static func deepSlotDocument(depth: Int) -> PenDocument {
            var body = PenNode(
                id: "Slot0", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(slot: ["rectangle"]))
            )
            for level in stride(from: depth - 1, through: 0, by: -1) {
                body = PenNode(
                    id: "F\(level)", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: [body]))
                )
            }
            let component = PenNode(
                id: "Card0", common: PenNodeCommon(reusable: true), kind: .frame(PenNode.FrameData(children: [body]))
            )

            let leaf = PenNode(id: "Leaf0", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
            let leafValue = (try? JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode([leaf])))
                ?? .array([])
            let override = PenDescendantOverride(properties: [PenNodePatcher.childrenKey: leafValue])
            let instance = PenNode(
                id: "Inst0", common: PenNodeCommon(),
                kind: .ref(PenNode.RefData(ref: "Card0", descendants: ["Slot0": override]))
            )
            return PenDocument(children: [component, instance])
        }
    }

    /// A document deep enough that building or freeing it the ordinary way would touch a
    /// normal thread's stack — held here so neither ever runs on one.
    ///
    /// `EditableDocument.init(from:)`'s own `document` parameter keeps the *original*,
    /// unflattened tree alive until `init` returns, and that parameter's deinit — like any
    /// PenNode tree's — still recurses one call per level
    /// (`project/2026-09-26-debug-stack-depth.md`). Building the document here, on
    /// ``StackHighWater``'s generously-stacked thread, absorbs that cost outside of
    /// whatever a test measures; ``release()`` does the same for freeing it.
    private final class DeepSlotDocumentHolder {
        /// The constructed document, or `nil` if it has been released.
        private(set) var document: EditableDocument?

        /// Builds the document on a thread with room for it.
        ///
        /// - Parameter depth: How many frames nest inside the component's body.
        init(depth: Int) {
            document = StackHighWater.measure {
                EditableDocument(from: DescendantWalkStackTests.deepSlotDocument(depth: depth))
            }.result
        }

        /// Frees the document on a thread with room for it.
        func release() {
            _ = StackHighWater.measure {
                self.document = nil
            }
        }
    }

#endif
