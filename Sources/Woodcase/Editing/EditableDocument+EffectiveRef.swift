//
//  EditableDocument+EffectiveRef.swift
//  Woodcase
//

import Foundation

/// Which component a `ref` node actually places.
///
/// The flat store holds a component's *authored* wiring, and for a `ref` on a page
/// that is the whole answer. It is not the whole answer for a `ref` **inside** a
/// component: an instance may repoint one of the component's nested refs — the
/// natural way to say "this tab is the current one" — by writing `ref` into its own
/// `descendants` map, and ``PenRefExpander`` honours that when it expands.
///
/// Every reader that has to agree with the expander asks here. Reading the authored
/// `ref` instead is what left a repointed instance with no rect and its *old*
/// component's children: the expansion produced `Sht01/Tab01/CurC` while the tree
/// walk and the address resolver were both looking up `Sht01/Tab01/PlnC`.
///
/// ## What can repoint what
///
/// Only the instance a node sits **directly** inside can repoint it, because that is
/// the only override the expander applies before it recurses: a `descendants` key
/// with no `/` is patched onto the component's own subtree, while a key with one is
/// applied after expansion, when the nested ref is already gone. So the chain a
/// caller passes matters only through its last element — but the whole chain is
/// needed to resolve *that* element, which may itself have been repointed.
public extension EditableDocument {
    /// The `ref` payload a node carries once the instance it sits directly inside has
    /// applied its descendant override to it.
    ///
    /// - Parameters:
    ///   - nodeID: The node in the flat store — a `ref` node, for a non-`nil` answer.
    ///   - chain: The `ref` node ids the node sits inside, outermost first. Empty for
    ///     a node in the document's own tree, where the authored payload is the answer.
    /// - Returns: The ref payload as the expansion will see it, or `nil` when the node
    ///   is missing or is not a `ref` there. Only `ref` and `descendants` are settled:
    ///   an override that names neither is skipped whole, so `rootOverrides` may still
    ///   be the authored ones. Read them from the node, not from here.
    ///
    /// - Note: A node the file does not author as a `ref` is never one here, however
    ///   an override rewrites it. This is asked of every node of every tree read, and
    ///   an override that swaps a plain node's whole `type` for `ref` — the one case
    ///   the shortcut misses — is not a shape the format's own editor writes.
    func effectiveRefData(of nodeID: String, insideInstances chain: [String]) -> PenNode.RefData? {
        // Settled outermost first, one step per element, so a caller's chain costs a
        // loop rather than a stack frame per element.
        var enclosing: PenNode.RefData?
        for element in chain {
            enclosing = effectiveRefData(of: element, enclosedBy: enclosing)
        }
        return effectiveRefData(of: nodeID, enclosedBy: enclosing)
    }

    /// The `ref` payload a node carries once the instance it sits directly inside has
    /// applied its descendant override to it, given that instance's own payload.
    ///
    /// One step of ``effectiveRefData(of:insideInstances:)``. A walk that goes down an
    /// instance chain already holds the enclosing payload — it settled it one level up —
    /// so it passes that here instead of re-settling the whole chain at every node.
    ///
    /// - Parameters:
    ///   - nodeID: The node in the flat store — a `ref` node, for a non-`nil` answer.
    ///   - enclosing: The settled payload of the instance the node sits directly
    ///     inside, or `nil` when it sits in none, or in one that is no `ref` in the
    ///     store — where the authored payload is the answer.
    /// - Returns: The ref payload as the expansion will see it, or `nil` when the node
    ///   is missing or is not a `ref` there.
    func effectiveRefData(of nodeID: String, enclosedBy enclosing: PenNode.RefData?) -> PenNode.RefData? {
        guard let node = componentNode(nodeID), case let .ref(authored) = node.kind else { return nil }
        guard let override = enclosing?.descendants?[nodeID],
              Self.canRewriteRefPayload(override),
              case let .ref(patched) = PenNodePatcher.applyOverride(to: node, override: override).kind
        else { return authored }
        return patched
    }

    /// Where an instance lands once its alias chain is followed: the component root it
    /// clones, and every component the expansion has passed through to get there.
    struct ComponentPlacement: Friendly {
        /// The id of the node the expansion clones — the far end of the alias chain.
        public var rootID: String

        /// The component ids on the expansion chain below this instance: those it was
        /// placed inside, its own, and every alias link it followed. A `ref` below it
        /// that names one of these is circular, and stays as written.
        public var chain: Set<String>

        /// Creates a placement.
        ///
        /// - Parameters:
        ///   - rootID: The cloned node's id.
        ///   - chain: The component ids on the expansion chain.
        public init(rootID: String, chain: Set<String>) {
            self.rootID = rootID
            self.chain = chain
        }
    }

    /// Where a `ref` payload lands, inside instances of the given components.
    ///
    /// Mirrors ``PenRefExpander``'s `resolveChain` step for step: a payload naming a
    /// component already on the chain is circular and places nothing; an alias is
    /// followed until a non-`ref` component, a component already passed, or one the
    /// registry lacks — where the clone is whatever the walk stopped on.
    ///
    /// - Parameters:
    ///   - refData: The payload, as the enclosing instance settled it.
    ///   - chain: The component ids already on the expansion chain — empty in the
    ///     document's own tree.
    /// - Returns: The placement, or `nil` for a circular payload or one that names no
    ///   reusable component — the two cases the expansion leaves as written.
    func componentPlacement(of refData: PenNode.RefData, onChain chain: Set<String>) -> ComponentPlacement? {
        guard !chain.contains(refData.ref), var component = reusableComponent(refData.ref) else { return nil }

        var passed = chain
        passed.insert(refData.ref)
        while case let .ref(inner) = component.kind {
            guard !passed.contains(inner.ref), let next = reusableComponent(inner.ref) else { break }
            passed.insert(inner.ref)
            component = next
        }
        return ComponentPlacement(rootID: component.id, chain: passed)
    }

    /// Whether an override could change what a `ref` node places, or how.
    ///
    /// Only two of a ref's keys are read here — `ref` and `descendants` — so an
    /// override that names neither leaves the payload as authored, and the patch (a
    /// JSON round trip of the node) is skipped. A whole-node replacement names `type`
    /// and can rewrite either.
    private static func canRewriteRefPayload(_ override: PenDescendantOverride) -> Bool {
        override.isObjectReplacement
            || override.properties["ref"] != nil
            || override.properties["descendants"] != nil
    }

    /// The id of the component root a `ref` node clones, following ref chains.
    ///
    /// Mirrors what ``PenRefExpander`` does when it expands a ref: the registry is
    /// ``componentRegistry`` — nodes marked `reusable` — and a component that is
    /// itself a `ref` is followed until a non-`ref` one is reached or the chain
    /// revisits a component it has already passed through.
    ///
    /// - Parameters:
    ///   - nodeID: The candidate `ref` node's id.
    ///   - chain: The `ref` node ids it sits inside, outermost first.
    /// - Returns: The cloned component's root id, or `nil` when the node is not a
    ///   `ref` or names no reusable component — the two cases where expansion leaves
    ///   the node exactly as authored.
    func componentRootID(placedBy nodeID: String, insideInstances chain: [String]) -> String? {
        guard let refData = effectiveRefData(of: nodeID, insideInstances: chain) else { return nil }
        return componentRootID(of: refData)
    }

    /// The id of the component root a `ref` **payload** clones, following ref chains.
    ///
    /// The same answer as ``componentRootID(placedBy:insideInstances:)``, for a payload
    /// the caller already holds rather than one it names. A `ref` an instance writes
    /// into a slot is such a case: it exists only inside that instance's `descendants`
    /// map, so there is no node in the flat store to ask about.
    ///
    /// - Parameter refData: The payload, as authored or as the enclosing instance
    ///   settled it.
    /// - Returns: The cloned component's root id, or `nil` when the payload names no
    ///   reusable component — the case where expansion leaves the ref as it stands.
    func componentRootID(of refData: PenNode.RefData) -> String? {
        componentPlacement(of: refData, onChain: [])?.rootID
    }
}
