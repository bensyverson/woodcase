//
//  CopyAssignment.swift
//  Woodcase
//

import Foundation

/// Where the properties given to a `cp` land, and what they land as.
///
/// A copy is several writes wearing one verb. `common.name=Checkout` belongs on the
/// copy's own root; `Header/Title/kind.content=Checkout` belongs on a node *inside*
/// the copy, which does not exist until the copy has been made — and, when the copy is
/// a component instance, has no storage of its own and must be written as an override
/// instead. This is the one place those three decisions are made, so
/// `woodcase cp` on argv and `{"op":"cp"}` in a batch cannot mean different things by
/// the same key.
///
/// ```swift
/// let split = CopyAssignment.split(["common.name": .string("Chip"),
///                                   "Label/kind.content": .string("Hello")])
/// split.root        // ["common.name": "Chip"]
/// split.descendants // ["Label": ["kind.content": "Hello"]]
/// ```
///
/// ## Topics
///
/// ### Splitting a key
/// - ``Destination``
/// - ``destination(of:)``
/// - ``split(_:)``
///
/// ### Repeating a copy
/// - ``rowPlaceholder``
/// - ``substituting(_:into:)``
/// - ``decodeRows(_:)``
///
/// ### Writing inside the copy
/// - ``address(inside:path:)``
/// - ``assignment(to:props:in:)``
public enum CopyAssignment {
    // MARK: - Splitting a key

    /// Where one of a copy's properties is written.
    public enum Destination: Friendly {
        /// The copy's own root node.
        case root

        /// A node inside the copy, named by a path from the copy's root.
        case descendant(path: String)
    }

    /// Resolves one key a `cp` was given into where its value lands and under which
    /// property name.
    ///
    /// **This is the seam.** Every form a copy's key may take is decided here and
    /// nowhere else, so a new form — a parameter name declared in a component's
    /// `common.metadata._props`, say — is added by extending this one function and is
    /// then understood by the verb, by the batch op and by `--each` rows at once.
    ///
    /// A property path never contains a slash and a name path always does, so the last
    /// slash is the seam. A node whose *name* contains a slash is written `#id` in
    /// every path this tool prints, so it cannot be mistaken for one.
    ///
    /// A key with no slash may still name a node inside the copy, if the source
    /// *publishes* it: a component's ``ComponentParameter`` list — its
    /// `common.metadata._props` — maps a published name to a descendant path and the
    /// property there, so `label` means `Body/Title/kind.content` and is routed as if
    /// it had been written that way. A name the component root already has a property
    /// of is not routed: the raw property wins, which is what
    /// ``ComponentParameter/collidesWithProperty`` marks.
    ///
    /// - Parameters:
    ///   - key: The key as written — `"common.name"`, `"Header/Title/kind.content"`,
    ///     `"label"`.
    ///   - parameters: The parameters the source publishes. Empty by default, which is
    ///     every source that is not a component.
    /// - Returns: Where the value lands, and the property name it lands under.
    public static func destination(
        of key: String,
        parameters: [ComponentParameter] = []
    ) -> (destination: Destination, property: String) {
        guard let seam = key.lastIndex(of: NodeAddress.separator) else {
            guard let parameter = parameters.first(where: { $0.name == key }),
                  !parameter.collidesWithProperty,
                  let property = parameter.property
            else { return (.root, key) }
            return (.descendant(path: parameter.path), property)
        }
        return (
            .descendant(path: String(key[key.startIndex ..< seam])),
            String(key[key.index(after: seam)...])
        )
    }

    /// Splits a copy's properties into the ones for its root and the ones for the
    /// nodes inside it.
    ///
    /// - Parameters:
    ///   - properties: Every key the caller gave the copy, root and path-keyed alike.
    ///   - parameters: The parameters the source publishes, so a published name is
    ///     routed to the node it names.
    /// - Returns: The root's own properties, and the properties for each node inside
    ///   the copy keyed by its name path from the copy's root.
    public static func split(
        _ properties: [String: AnyCodable],
        parameters: [ComponentParameter] = []
    ) -> (root: [String: AnyCodable], descendants: [String: [String: AnyCodable]]) {
        var root: [String: AnyCodable] = [:]
        var descendants: [String: [String: AnyCodable]] = [:]
        for (key, value) in properties {
            switch destination(of: key, parameters: parameters) {
            case let (.root, property):
                root[property] = value
            case let (.descendant(path), property):
                descendants[path, default: [:]][property] = value
            }
        }
        return (root, descendants)
    }

    // MARK: - Repeating a copy

    /// The 1-based placeholder a repeated copy substitutes into every value it carries.
    ///
    /// Identical names break path addressing, so a copy made N times needs somewhere to
    /// put the counter. It is substituted into *values*, never into keys: a key names a
    /// node inside the source, which does not change from one copy to the next.
    public static let rowPlaceholder = "{n}"

    /// Replaces every ``rowPlaceholder`` in a value's strings with `n`, recursively
    /// through arrays and objects.
    ///
    /// - Parameters:
    ///   - n: The 1-based copy number.
    ///   - value: The value as written.
    /// - Returns: The value with the placeholder substituted.
    public static func substituting(_ n: Int, into value: AnyCodable) -> AnyCodable {
        switch value {
        case let .string(text):
            .string(text.replacingOccurrences(of: rowPlaceholder, with: String(n)))
        case let .array(items):
            .array(items.map { substituting(n, into: $0) })
        case let .dictionary(fields):
            .dictionary(fields.mapValues { substituting(n, into: $0) })
        case .null, .bool, .int, .double:
            value
        }
    }

    /// Replaces every ``rowPlaceholder`` across a set of properties.
    ///
    /// - Parameters:
    ///   - n: The 1-based copy number.
    ///   - properties: The properties as written.
    /// - Returns: The properties with the placeholder substituted in every value.
    public static func substituting(
        _ n: Int,
        into properties: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        properties.mapValues { substituting(n, into: $0) }
    }

    /// Decodes a rows file: one JSON object per line, in order.
    ///
    /// The same shape a batch file has, for the same reason — a row is a line, so a
    /// generator can append to it and a reader can count it — and blank lines are
    /// skipped so a hand-written file can breathe. Each object's keys are exactly the
    /// keys a `cp` takes.
    ///
    /// - Parameter text: The contents of a `.jsonl` rows file.
    /// - Returns: The rows, in file order.
    /// - Throws: ``BatchError/malformedRow(row:reason:)`` naming the 1-based row that
    ///   would not decode.
    public static func decodeRows(_ text: String) throws -> [[String: AnyCodable]] {
        let decoder = JSONDecoder()
        var rows: [[String: AnyCodable]] = []
        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            do {
                try rows.append(decoder.decode([String: AnyCodable].self, from: Data(line.utf8)))
            } catch {
                throw BatchError.malformedRow(
                    row: offset + 1, reason: DecodingReason.describe(error, root: "it")
                )
            }
        }
        return rows
    }

    // MARK: - Writing inside the copy

    /// An address that walks into a copy from the id the document just gave it.
    ///
    /// Anchoring at the new root's forced id (`#k2Bq9/Title`) is what makes "inside the
    /// copy" literal rather than hopeful: the same name path would otherwise resolve
    /// against the source the copy was duplicated from.
    ///
    /// - Parameters:
    ///   - rootID: The id of the copy's root.
    ///   - path: The name path beneath it.
    /// - Returns: The anchored address, or `nil` when `path` is not a path at all.
    public static func address(inside rootID: String, path: String) -> NodeAddress? {
        NodeAddress("\(NodeAddress.marker(forID: rootID))\(NodeAddress.separator)\(path)")
    }

    /// The write that puts `props` on one node inside a copy.
    ///
    /// Copying a reusable component makes a `ref`, and a node inside an instance has no
    /// storage of its own: the edit belongs in the instance's `descendants` map, keyed
    /// by raw .pen names. Placing a component and titling it is the single most common
    /// move, so the write translates rather than refuse — the caller writes the one
    /// vocabulary every read prints, and the override is stored under whichever one the
    /// target keys by. The translation itself is ``BatchApplier``'s, applied to every
    /// `override` however it was written.
    ///
    /// A path that resolves to nothing takes the `set` branch, so the miss is still
    /// reported against the address the caller wrote.
    ///
    /// - Parameters:
    ///   - target: The address of the node inside the copy.
    ///   - props: The properties assigned there, keyed by ``NodePropertyCodec`` path or
    ///     by raw .pen name.
    ///   - document: The document, for resolving which side of the seam `target` is on.
    /// - Returns: A `set` for a node with storage of its own, an `override` for a node
    ///   inside a component instance.
    public static func assignment(
        to target: NodeAddress,
        props: [String: AnyCodable],
        in document: EditableDocument
    ) -> BatchOperation {
        guard let resolved = try? document.resolve(target), resolved.descendantKey != nil else {
            return .set(BatchOperation.SetOp(target: target, props: props))
        }
        return .override(BatchOperation.OverrideOp(target: target, props: props))
    }
}
