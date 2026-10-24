//
//  EditRefusal.swift
//  Woodcase
//

import Foundation

/// Why ``EditPlanner`` would not plan an edit: a stable code, the property it is
/// about, the form that would have been accepted, and a sentence for a person.
///
/// An inspector branches on ``code`` and shows ``expected`` beside the field that was
/// refused; the CLI prints ``message``. Nothing has been written when one is thrown.
///
/// ```swift
/// do {
///     _ = try EditPlanner.plan(.set(["common.opacity": 7]), at: address, in: document)
/// } catch {
///     error.code      // .outOfRange
///     error.property  // "common.opacity"
///     error.expected  // "0 to 1, a fraction"
/// }
/// ```
///
/// Loading is never refused. A file holding an opacity of 7 opens, and an operation
/// that did not come through the planner — a merge, an undo, a peer's write — is
/// applied as it is; see ``EditPlanner``.
public struct EditRefusal: Error, Friendly {
    /// The family a refusal belongs to: the token a program branches on.
    ///
    /// The raw values are stable; a sentence may be reworded, a code does not move.
    public enum Code: String, Friendly, CaseIterable {
        // MARK: Addressing

        /// The address names no node.
        case addressNotFound

        /// The address names more than one node.
        case ambiguousAddress

        /// An override names a node the instance's component does not hold.
        case overrideTargetNotFound

        /// An override was addressed at a node that is neither an instance nor inside one.
        case overrideOutsideInstance

        /// A set, bind or unbind was aimed at a node inside a component instance. Writing
        /// there changes this instance only, not the component, so it has to be asked for
        /// as an ``EditIntent/override(_:unset:)``; ``EditRefusal/suggestion`` is its
        /// payload.
        case setInsideInstance

        /// The intent carried nothing to write and nothing to unset.
        case noProperties

        // MARK: Keys and forms

        /// The node's type has no such property.
        case unknownProperty

        /// The value is not one of the forms the property accepts.
        case invalidForm

        /// The key cannot be overridden on an instance root — it belongs to the `ref`
        /// node, or to the format.
        case reservedOverrideKey

        /// A key names a parameter the component publishes, whose declared path names
        /// nothing inside it.
        case parameterPathNotFound

        // MARK: Value constraints

        /// A number lies outside the property's range.
        case outOfRange

        /// A number falls between the property's steps — a fractional polygon count.
        case offStep

        // MARK: Variables

        /// A `$name` names no variable the document defines.
        case undefinedVariable

        /// A `$name` names a variable of a type the property does not take.
        case variableTypeMismatch

        /// An unbind named a property that holds no variable binding.
        case notBound

        // MARK: Layout

        /// An `x` or `y` on a node its parent's layout places, which would be stored and
        /// ignored.
        case positionIgnoredByLayout

        /// A dash on a stroke of per-side widths, whose bands dashes cannot flow around.
        case dashOnPerSideStroke

        // MARK: Structure

        /// A group, frame selection or ungroup named nothing to act on.
        case noNodes

        /// A group, frame selection or ungroup reached into a component instance, whose
        /// nodes are its component's: aimed at a node inside one, or at a slot's content.
        case insideInstance

        /// An ungroup was aimed at a node that is neither a group nor a frame.
        case notAGroup

        /// Use as Default Text Style was aimed at a node that is not a text.
        case notAText

        /// A slot intent — Replace Content, Empty Slot, Reset Slot, Suggested Components —
        /// was aimed at a node that is not a slot.
        case notASlot

        /// Make Slot was aimed where a slot means nothing: a node that is not a frame, a
        /// frame outside every component, or a component's own frame, which every
        /// instance needs as the part that selects it.
        case slotNotAllowed

        /// A move would put a node inside itself: the parent named is the node or one of
        /// its descendants. ``EditRefusal/detail`` names both
        /// (``Detail/wouldCreateCycle(nodeID:targetParentID:)``).
        case wouldCreateCycle

        // MARK: Components

        /// The edit would make components contain each other — a component that renders
        /// an instance of itself, directly or through others (<doc:ComponentLoops>).
        /// ``EditRefusal/detail`` is the loop (``Detail/componentLoop(_:)``).
        case wouldCloseComponentLoop

        /// The edit would remove a component its instances point at — a delete, or an
        /// ungroup of a component frame — turning them into plain frames.
        /// ``EditRefusal/detail`` names the component and its instances
        /// (``Detail/componentHasInstances(componentID:instanceIDs:)``).
        case componentHasInstances

        /// The edit would replace a component with a node of a different type while
        /// instances point at it. ``EditRefusal/detail`` names them
        /// (``Detail/componentTypeChange(componentID:from:to:instanceIDs:)``).
        case componentTypeChange

        // MARK: Everything else

        /// The write names a Woodcase-owned key at its storage path; ``suggestion`` writes
        /// it at its natural path instead (``EditingError/storedAtNaturalPath(nodeID:path:naturalPath:)``).
        case storedAtNaturalPath

        /// The document refused the edit for a reason no other code names; ``errorCode``
        /// says which.
        case documentRefused
    }

    /// Creates a refusal.
    ///
    /// - Parameters:
    ///   - code: The family it belongs to.
    ///   - address: The address the intent was aimed at, as written.
    ///   - property: The property path or raw key refused, when one was.
    ///   - expected: The form or range that would have been accepted, when there is one.
    ///   - suggestion: A literal write that would have been accepted, when there is one.
    ///   - message: One sentence: what was refused, and what to do instead.
    ///   - errorCode: The ``EditingError/code`` or ``BatchError/code`` the refusal came
    ///     from, when it came from one.
    ///   - nested: Where inside the property's value the refused value sits, when the
    ///     refusal is about one.
    ///   - detail: What the refusal names, as values, when it names something.
    public init(
        code: Code,
        address: String,
        property: String? = nil,
        expected: String? = nil,
        suggestion: String? = nil,
        message: String,
        errorCode: String? = nil,
        nested: NestedLocation? = nil,
        detail: Detail? = nil
    ) {
        self.code = code
        self.address = address
        self.property = property
        self.expected = expected
        self.suggestion = suggestion
        self.message = message
        self.errorCode = errorCode
        self.nested = nested
        self.detail = detail
    }

    /// The family this refusal belongs to.
    public var code: Code

    /// The address the intent was aimed at, as written.
    public var address: String

    /// The property path or raw key refused, or `nil` when the refusal is about the
    /// address rather than one property.
    public var property: String?

    /// The form or range that would have been accepted — `"0 to 1, a fraction"`, `"a
    /// $color variable"` — or `nil` when there is none to state.
    public var expected: String?

    /// A write that would have been accepted, ready to show or paste —
    /// `common.layoutPosition=absolute` — or `nil`.
    public var suggestion: String?

    /// One sentence: what was refused, and what to do instead.
    public var message: String

    /// The ``EditingError/code`` or ``BatchError/code`` this refusal came from, or `nil`
    /// for one the planner raised itself.
    public var errorCode: String?

    /// Where inside ``property``'s value the refused value sits — the paint or effect
    /// layer and the key — or `nil` when the refusal is about the property itself.
    ///
    /// The structured twin of the location the ``message`` spells: an inspector places
    /// the refusal under layer ``NestedLocation/layerIndex`` without parsing a sentence.
    public var nested: NestedLocation?

    /// What the refusal names, as values — the loop a move would close, the component
    /// whose instances a removal would orphan, the nodes an address could mean — or `nil`
    /// when it names nothing beyond ``address`` and ``property``.
    public var detail: Detail?
}
