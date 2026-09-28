//
//  BatchApplier+Divergence+Structural.swift
//  Woodcase
//

import Foundation

/// Where a write's consequences that come from the document's own state — a variable
/// table it grew, a placement it chose, an instance it detached — are turned into the
/// same divergence sentence as any other divergence.
///
/// Split out of the property- and override-level divergences in
/// `BatchApplier+Divergence.swift` for size: that file plans what a write's own
/// properties imply; this one plans what the rest of the document does in response.
/// Both share one planner, described there.
extension BatchApplier {
    // MARK: - Document tables

    /// What a `var` line carrying a themed value has to say.
    ///
    /// A themed value is several facts on one line — one per option — and the line's own
    /// report says only `applied  document`, so the values a caller cannot see are
    /// echoed back the way `vars set` prints them. This is a ``WriteDivergence/Severity/note``
    /// rather than a warning: writing a token per theme option is the point of the op,
    /// not a surprise. The axes it grew are named in the same sentence, because
    /// registering them is the half of the write nothing else reports.
    ///
    /// - Parameters:
    ///   - op: The line as it was written.
    ///   - registrations: The axes the line creates or widens.
    /// - Returns: The note, or `nil` for a plain value — which is exactly what it looks
    ///   like and earns no sentence.
    static func themedVariable(
        _ op: BatchOperation.VariableOp,
        registering registrations: [ThemeAxisRegistrar.Registration]
    ) -> WriteDivergence? {
        guard case let .themed(variants) = op.value.value else { return nil }
        let options = variants.map { variant in
            "\(pin(of: variant.theme)) \(spelling(ofValue: variant.value))"
        }.joined(separator: ", ")
        let grown = registrations.isEmpty
            ? ""
            : " — " + registrations.map { "the axis \($0.name) now offers \($0.options.joined(separator: ", "))" }
            .joined(separator: ", and ")
        return WriteDivergence(
            kind: .themedVariable,
            severity: .note,
            target: op.name,
            requested: "a themed \(op.value.type.rawValue) value for \(op.name)",
            applied: options,
            note: "\(op.name) is a \(op.value.type.rawValue) per theme option: \(options)\(grown)"
        )
    }

    /// A variant's theme pin as the echo reads it: `axis=option` pairs, or `*` for the
    /// variant the resolver falls back to.
    private static func pin(of theme: [String: String]?) -> String {
        guard let theme, !theme.isEmpty else { return "*" }
        return theme.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// A variable's stored value as a sentence reads it — a string bare, since a colour
    /// in quotes reads as a caption rather than a value.
    private static func spelling(ofValue value: AnyCodable) -> String {
        guard case let .string(text) = value else { return spelling(of: value) }
        return text
    }

    // MARK: - Structural consequences

    /// The divergence a root-level placement implies.
    ///
    /// ``placedAtRoot(_:in:coordinates:)`` gives a root-level node somewhere empty to
    /// be when it did not say where, which is a coordinate the caller never wrote.
    ///
    /// - Parameters:
    ///   - placed: The node as it will be inserted.
    ///   - authored: The node as the caller supplied it.
    ///   - coordinates: Where the authored coordinates came from.
    /// - Returns: The divergence, or `nil` when the placement changed nothing.
    static func placement(
        of placed: PenNode,
        from authored: PenNode,
        coordinates: RootCoordinates
    ) -> WriteDivergence? {
        guard placed.common.x != authored.common.x || placed.common.y != authored.common.y
        else { return nil }
        let name = placed.common.name ?? placed.id
        let asked = position(of: authored)
        let applied = position(of: placed) ?? "somewhere clear"
        let remedy = coordinates == .copied
            ? "pass common.x and common.y alongside the copy to choose"
            : "write common.x and common.y to choose"
        return WriteDivergence(
            kind: .rootPlacement,
            target: name,
            requested: asked ?? "no coordinates",
            applied: applied,
            note: "\(name) was placed at \(applied), clear of the artboards already "
                + "there — \(remedy)"
        )
    }

    /// The divergence a delete that detached instances implies.
    ///
    /// - Parameters:
    ///   - instanceIDs: The instances the delete detaches first.
    ///   - componentID: The component being removed.
    ///   - document: The document, for the names.
    /// - Returns: The divergence, or `nil` when the delete stranded nothing.
    static func detachment(
        of instanceIDs: [String],
        removing componentID: String,
        in document: EditableDocument
    ) -> WriteDivergence? {
        guard !instanceIDs.isEmpty else { return nil }
        let name = document.node(id: componentID)?.common.name ?? componentID
        let paths = instanceIDs.map { document.namePath(of: $0) }
        let count = instanceIDs.count
        let subject = count == 1
            ? "1 instance of it into a standalone copy"
            : "\(count) instances of it into standalone copies"
        return WriteDivergence(
            kind: .detachedInstances,
            target: name,
            requested: "removing \(name)",
            applied: "detaching \(count == 1 ? "1 instance" : "\(count) instances"), then removing \(name)",
            note: "removing \(name) detached \(subject) first: \(paths.joined(separator: ", "))"
        )
    }

    // MARK: - Spelling

    /// A root node's coordinates as a sentence reads them, or `nil` when it has none.
    private static func position(of node: PenNode) -> String? {
        let x = literal(node.common.x)
        let y = literal(node.common.y)
        guard x != nil || y != nil else { return nil }
        return "x \(x ?? "unset"), y \(y ?? "unset")"
    }

    /// A `PenValue`'s literal number as text, or `nil` when it is absent or a reference.
    private static func literal(_ value: PenValue<Double>?) -> String? {
        guard case let .literal(number)? = value else { return nil }
        return number.rounded() == number && abs(number) < 1e15
            ? String(Int64(number))
            : String(number)
    }
}
