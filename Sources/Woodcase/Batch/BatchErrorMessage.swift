//
//  BatchErrorMessage.swift
//  Woodcase
//

import Foundation

/// Turns an editing failure into the sentence a report line — or a CLI verb — carries.
///
/// ## The convention
///
/// Every message here is one sentence in three parts:
///
/// 1. **the subject**, named the way the caller can address it again: a name path where
///    the node is in the document, otherwise the address, id or key exactly as typed;
/// 2. **what happened**, in the present tense;
/// 3. **the remedy**, separated by ` — ` and carrying at least one backticked literal:
///    the `woodcase` command to run, or the exact text to write.
///
/// The backtick is the machine-checkable part, and
/// `EditingErrorRemedyTests` walks every case of ``EditingError`` and ``BatchError``
/// asserting all three. A message that cannot name a remedy has no business being a
/// refusal — the caller would be left guessing.
///
/// ``EditingError`` and ``BatchError`` carry ids and raw keys, so part 1 needs the
/// document, to turn an id into ``EditableDocument/namePath(of:)-(String)``. Part 3
/// needs to know where the reader is standing, which is ``RemedyDialect``.
///
/// The CLI prints these verbatim for single-verb failures too, so a `set` that fails on
/// its own says exactly what the same `set` says inside a batch — only the remedy
/// changes dialect.
public enum BatchErrorMessage {
    /// Describes a failure in one sentence.
    ///
    /// - Parameters:
    ///   - error: The failure, usually an ``EditingError`` or a ``BatchError``.
    ///   - document: The document the operation ran against, for name paths.
    ///   - dialect: Which grammar the remedy is written in. Defaults to ``RemedyDialect/batch``,
    ///     which is what a batch report line wants.
    /// - Returns: A sentence naming what failed and what to do about it.
    public static func describe(
        _ error: any Error,
        in document: EditableDocument,
        dialect: RemedyDialect = .batch
    ) -> String {
        if let editing = error as? EditingError { return describe(editing, in: document, dialect: dialect) }
        if let batch = error as? BatchError { return describe(batch, dialect: dialect) }
        return "\(error)"
    }

    // MARK: - Batch grammar

    /// Describes a ``BatchError`` in one sentence.
    ///
    /// Unlike ``EditingError``, a batch-grammar failure never needs a document to
    /// resolve — every case already carries the address or path it names as text — so
    /// this is safe to call before a document exists at all, as `apply` does for a
    /// batch file that will not even decode.
    ///
    /// - Parameters:
    ///   - error: The batch-grammar failure.
    ///   - dialect: Which grammar the remedy is written in.
    /// - Returns: A sentence naming what failed and what to do about it.
    public nonisolated static func describe(_ error: BatchError, dialect: RemedyDialect = .batch) -> String {
        let file = dialect.file
        switch error {
        case let .malformedLine(line, reason):
            return sentence(
                "line \(line) is not a batch operation: \(reason)",
                batch: "a batch is JSONL — one JSON object per line, each with an \"op\" key; "
                    + "run `woodcase apply --help` for the grammar",
                command: "a batch is JSONL — one JSON object per line, each with an \"op\" key; "
                    + "run `woodcase apply --help` for the grammar",
                in: dialect
            )

        case let .malformedRow(row, reason):
            return sentence(
                "row \(row) is not a JSON object of properties: \(reason)",
                batch: #"write each row as one object, like `{"common.name":"Chip 1"}`"#,
                command: #"write each row as one object, like `{"common.name":"Chip 1"}`"#,
                in: dialect
            )

        case let .copyPathNotInSource(row, key, source):
            let at = row.map { "row \($0) writes " } ?? ""
            return sentence(
                "\(at)\(key), but \(source) has no \(pathPart(of: key)) inside it, "
                    + "so the copy would have nowhere to put it",
                batch: "run `woodcase tree \(file) \(source)` to list the paths inside it, "
                    + "and key the property with one of them",
                command: "run `woodcase tree \(file) \(source)` to list the paths inside it, "
                    + "and key the property with one of them",
                in: dialect
            )

        case let .parameterPathNotFound(name, path, component):
            return sentence(
                "\(name) is a parameter \(component) publishes as \(path), but nothing inside "
                    + "\(component) answers to \(path), so the write would draw nothing",
                batch: "point the declaration at a node that exists — "
                    + #"`{"op":"set","target":"\#(component)","props":"#
                    + #"{"common.metadata._props.\#(name)":"<name path>"}}`"#,
                command: "run `woodcase tree \(file) \(component)` for the names inside it, then "
                    + "`woodcase set \(file) \(component) common.metadata._props.\(name)=<name path>`",
                in: dialect
            )

        case .emptyCopyRows:
            return sentence(
                "the copy list has no rows in it, so this cp would copy nothing",
                batch: #"write at least one row in `"each"`, or drop the field for a single copy"#,
                command: "write at least one row in the `--each` file, or drop the flag "
                    + "for a single copy",
                in: dialect
            )

        case let .copyTagWithRows(tag):
            return sentence(
                """
                this cp declares the tag \(tag) and an each list at once, but a tag names one \
                node and each makes several
                """,
                batch: "drop the `\"tag\"`, and address the copies by the `common.name` "
                    + "their rows give them",
                command: "drop the `--each`, or address the copies by the `common.name` "
                    + "their rows give them",
                in: dialect
            )

        case let .unnamedNode(type, locator):
            return sentence(
                "the \(type) at \(locator) has no name, so nothing could address it once inserted",
                batch: "give every node in the subtree a `\"name\"`",
                command: "give every node in the subtree a `\"name\"`",
                in: dialect
            )

        case let .literalRootOverridesKey(locator):
            return sentence(
                """
                the ref at \(locator) writes a literal `rootOverrides` key, which the .pen \
                format does not have — a ref's root overrides are its own top-level keys, \
                so this one reads back as an override named "rootOverrides", patching a \
                property no node has
                """,
                batch: """
                write the overrides as top-level keys on the ref itself \
                (`{"type":"ref","ref":"…","width":80}`), or set them afterwards with \
                `{"op":"set","target":"…","props":{"kind.rootOverrides":{"width":80}}}`
                """,
                command: """
                write the overrides as top-level keys on the ref itself \
                (`{"type":"ref","ref":"…","width":80}`), or set them afterwards with \
                `woodcase set \(file) <ref> kind.rootOverrides='{"width":80}'`
                """,
                in: dialect
            )

        case let .replacementIDMismatch(address, supplied, kept):
            return sentence(
                """
                the replacement for \(address) writes the id \(supplied), but a replace keeps \
                the target's own id, \(kept)
                """,
                batch: #"write `"id": "\#(kept)"` on the root, or leave the id out"#,
                command: #"write `"id": "\#(kept)"` on the root, or leave the id out"#,
                in: dialect
            )

        case let .setInsideInstance(address, instancePath):
            return sentence(
                """
                \(address) is inside the component instance \(instancePath), which stores no \
                properties of its own
                """,
                batch: """
                write it as `{"op":"override","target":"\(address)",…}` instead, using raw .pen \
                property names (content, not kind.content)
                """,
                command: """
                run `woodcase override \(file) \(address) name=value` instead, with raw .pen \
                property names (content, not kind.content)
                """,
                in: dialect
            )

        case let .structureInsideSlot(address, slotPath):
            return sentence(
                """
                \(address) is a child an instance injected into the slot \(slotPath), and lives \
                inside that slot's own children rather than in the document's tree
                """,
                batch: """
                write the list again: `{"op":"override","target":"\(slotPath)",\
                "props":{"children":[…]}}` with the children you want
                """,
                command: """
                write the list again: `woodcase override \(file) \(slotPath) children='[…]'` with \
                the children you want
                """,
                in: dialect
            )

        case let .overrideWithoutProperties(address):
            return sentence(
                "the override of \(address) has nothing to write: no property and no key to unset",
                batch: #"give it `"props"`, `"unset"`, or both"#,
                command: "give it a `key=value`, an `--unset key`, or both",
                in: dialect
            )

        case let .overrideOutsideInstance(address, path):
            return sentence(
                """
                \(address) is a node of its own (\(path)), not a node inside a component instance
                """,
                batch: """
                use `{"op":"set","target":"\(address)",…}`; only a path that steps through a ref \
                can be overridden
                """,
                command: """
                run `woodcase set \(file) \(address) key=value` instead; only a path that steps \
                through a component instance can be overridden
                """,
                in: dialect
            )

        case let .parentInsideInstance(address, instancePath):
            return sentence(
                """
                \(address) is inside the component instance \(instancePath), so a node added there \
                would have nowhere to live
                """,
                batch: """
                add to the component itself; `"parent"` has to name a node outside every \
                instance, because only a detached instance holds children of its own
                """,
                command: """
                add to the component itself, which `woodcase tree \(file)` locates; only a \
                detached instance holds children of its own
                """,
                in: dialect
            )

        case let .documentRevisionConflict(expected, actual):
            return sentence(
                "the document has changed: rev was \(expected), the document is now \(actual)",
                batch: "re-read it and rebuild this line with the current `rev`",
                command: "re-read it with `woodcase tree \(file)` and retry with the revision it prints",
                in: dialect
            )

        case let .guardConflict(node, address, expected, actual, writer):
            return sentence(
                """
                \(node) has changed since you read it\(moved(by: writer)): --guard pinned \
                \(expected), and it is now \(actual)
                """,
                batch: "re-read it, re-derive this line from what it says now, and pin the new `guard`",
                command: address.map {
                    """
                    re-read it with `woodcase get \(file) \($0)` and re-derive the write from what \
                    it says now
                    """
                } ?? "re-read it with `woodcase tree \(file)` and re-derive the write from what it says now",
                in: dialect
            )

        case let .guardNodeMissing(node):
            return sentence(
                """
                the guard names \(node), which this document does not hold — it was removed since \
                you read it, or the address is not the one you meant
                """,
                batch: "re-read the file and pin something it still holds in `guard`",
                command: "re-read it with `woodcase tree \(file)` and pin something it still holds",
                in: dialect
            )

        case let .guardOnTag(tag):
            return sentence(
                """
                a guard cannot name @\(tag): guards are checked once, before any line of the batch \
                runs, so nothing a line creates exists yet
                """,
                batch: #"guard the parent you read instead: `"guard":{"node":"…","rev":"…"}`"#,
                command: "guard the node you read instead: `--guard <node>=<rev>`",
                in: dialect
            )

        case let .guardWithoutTarget(verb):
            return sentence(
                "a \(verb) line acts on no node, so a bare guard has nothing to pin",
                batch: #"name what it pins: `"guard":{"node":"…","rev":"…"}`"#,
                command: "name what it pins: `--guard <node>=<rev>`",
                in: dialect
            )
        }
    }

    /// The clause naming who moved a guarded node, or nothing when the log cannot say.
    ///
    /// An unattributed write — a write with no `--as` — is a real writer with no name,
    /// so it is *said*, not omitted: "nobody wrote this" and "we do not know who wrote
    /// this" are different answers and a caller acts on them differently.
    private nonisolated static func moved(by writer: String?) -> String {
        guard let writer else { return "" }
        return writer == ActivityEvent.unattributed
            ? " (an unattributed write moved it)"
            : " (\(writer) moved it)"
    }

    // MARK: - Composing

    /// Joins a statement to whichever remedy the dialect calls for.
    ///
    /// - Parameters:
    ///   - statement: The subject and what happened to it.
    ///   - batch: The remedy for someone editing a batch file.
    ///   - command: The remedy for someone at a shell prompt.
    ///   - dialect: Which of the two the reader is holding. A script takes the batch
    ///     remedy: what it would correct is the JSON a batch line carries.
    /// - Returns: The two halves joined by the ` — ` the convention reserves for it.
    nonisolated static func sentence(
        _ statement: String,
        batch: String,
        command: String,
        in dialect: RemedyDialect
    ) -> String {
        switch dialect {
        case .batch, .script: "\(statement) — \(batch)"
        case .command: "\(statement) — \(command)"
        }
    }

    // MARK: - Naming

    /// The name-path half of a `cp` key, for the refusal that has to say what it could
    /// not find — `Header/Title` out of `Header/Title/kind.content`.
    nonisolated static func pathPart(of key: String) -> String {
        guard case let .descendant(path) = CopyAssignment.destination(of: key).destination
        else { return key }
        return path
    }

    /// A node named the way a message should name it: its path, and its id when
    /// the path is not obviously the id already.
    static func name(_ nodeID: String, in document: EditableDocument) -> String {
        let path = document.namePath(of: nodeID)
        return path == nodeID || path == NodeAddress.marker(forID: nodeID) ? path : "\(path) (\(nodeID))"
    }

    /// Candidate addresses, rendered as a comma-separated list a caller can paste.
    static func list(_ candidates: [NodeAddressCandidate]) -> String {
        candidates.map { "\($0.path) (\($0.id))" }.joined(separator: ", ")
    }
}
