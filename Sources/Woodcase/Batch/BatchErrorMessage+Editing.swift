//
//  BatchErrorMessage+Editing.swift
//  Woodcase
//

import Foundation

extension BatchErrorMessage {
    /// Describes an ``EditingError`` in one sentence, naming nodes by path.
    ///
    /// - Parameters:
    ///   - error: The refusal the document raised.
    ///   - document: The document it was raised against, for name paths.
    ///   - dialect: Which grammar the remedy is written in.
    /// - Returns: A sentence naming what failed and what to do about it.
    static func describe(
        _ error: EditingError,
        in document: EditableDocument,
        dialect: RemedyDialect = .batch
    ) -> String {
        let file = dialect.file
        switch error {
        case let .nodeNotFound(id):
            return sentence(
                "no node with id \(id) is in this document",
                batch: "check the address, or `\"tag\"` an earlier line that creates it",
                command: "run `woodcase tree \(file)` to list the addresses this document has",
                in: dialect
            )

        case let .duplicateNodeID(id):
            return sentence(
                "the id \(id) is already taken — by a node in this document, or by another node in the "
                    + "same subtree",
                batch: "pick an unused `\"id\"`, or leave it out and let the insert generate one",
                command: "pick an unused `\"id\"`, or leave it out and let `woodcase add` generate one",
                in: dialect
            )

        case let .invalidNodeID(id):
            return sentence(
                "\(id) cannot be a node id: an id is a non-empty string with no `/` in it, because `/` "
                    + "separates the segments of an address",
                batch: "give the node an `\"id\"` with no slash, or leave it out and let the insert generate one",
                command: "give the node an `\"id\"` with no slash, or leave it out and let `woodcase add` "
                    + "generate one",
                in: dialect
            )

        case let .parentNotFound(id):
            return sentence(
                "no node with id \(id) is in this document, so nothing can be added to it",
                batch: "address a parent that exists, or point `\"parent\"` at the `@tag` of an earlier line",
                command: "run `woodcase tree \(file)` to find the parent's address",
                in: dialect
            )

        case let .cannotHaveChildren(parentID):
            return sentence(
                """
                \(name(parentID, in: document)) is a \(type(of: parentID, in: document)), and only a \
                frame or a group can hold children
                """,
                batch: "point `\"parent\"` at a frame or a group",
                command: "run `woodcase tree \(file)` to find a frame to add to",
                in: dialect
            )

        case let .invalidIndex(index, count):
            return sentence(
                """
                position \(index) is out of range: that parent has \(count) \
                \(count == 1 ? "child" : "children")
                """,
                batch: "give `\"at\"` a value between 0 and \(count), or leave it out to append",
                command: "pass `--at` a value between 0 and \(count), or leave it out to append",
                in: dialect
            )

        case let .wouldCreateCycle(nodeID, targetParentID):
            return sentence(
                """
                \(name(nodeID, in: document)) cannot move into \(name(targetParentID, in: document)), \
                which is inside it
                """,
                batch: "point `\"parent\"` at a node outside the one being moved",
                command: "run `woodcase tree \(file)` to pick a parent outside the node being moved",
                in: dialect
            )

        // MARK: Documents

        case let .variableNotFound(name):
            return sentence(
                "no variable named \(name) is in this document",
                batch: "define it first with `{\"op\":\"var\",\"name\":\"\(name)\",…}`",
                command: """
                run `woodcase vars list \(file)` to see the ones that are, or \
                `woodcase vars set \(file) \(name)=<value>` to add it
                """,
                in: dialect
            )

        case let .variableAlreadyExists(name):
            return sentence(
                "a variable named \(name) is already in this document",
                batch: "write `{\"op\":\"var\",\"name\":\"\(name)\",\"value\":…}` to change the one that is there",
                command: "run `woodcase vars set \(file) \(name)=<value>` to change the one that is there",
                in: dialect
            )

        case let .importNotFound(alias):
            return sentence(
                "no import aliased \(alias) is in this document",
                batch: "check the document's `imports` map for the aliases it does declare",
                command: "check the document's `imports` map for the aliases it does declare",
                in: dialect
            )

        case let .importAlreadyExists(alias):
            return sentence(
                "an import aliased \(alias) is already in this document",
                batch: "choose another alias, or edit the entry already in the document's `imports` map",
                command: "choose another alias, or edit the entry already in the document's `imports` map",
                in: dialect
            )

        case let .themeAxisNotFound(name):
            return sentence(
                "no theme axis named \(name) is in this document",
                batch: "define it first with `{\"op\":\"theme-axis\",\"name\":\"\(name)\",\"options\":[…]}`",
                command: """
                run `woodcase vars list \(file)` to see the axes it defines, or \
                `woodcase vars axis add \(file) \(name)=<option>` to add one
                """,
                in: dialect
            )

        case let .themeAxisAlreadyExists(name):
            return sentence(
                "a theme axis named \(name) is already in this document",
                batch: """
                write `{"op":"theme-axis","name":"\(name)","options":[…]}` to add options to the one \
                that is there
                """,
                command: "run `woodcase vars axis add \(file) \(name)=<option>` to add options to it",
                in: dialect
            )

        case let .notARefNode(id):
            return sentence(
                "\(name(id, in: document)) is a \(type(of: id, in: document)), not a component instance",
                batch: "use `{\"op\":\"set\",…}` on a node of its own; only an instance takes an override",
                command: """
                run `woodcase set \(file) \(id) key=value` on a node of its own; only an instance \
                takes an override
                """,
                in: dialect
            )

        // MARK: Properties

        case let .unknownProperty(nodeID, key, nodeType):
            // A `ref` accepts three properties of its own; every other name a caller
            // writes at it is a property of the *component root* it shows, and that is
            // a root override rather than a property of the instance node.
            if let raw = rootOverrideKey(key, on: nodeID, in: document) {
                let address = document.namePath(of: nodeID)
                return sentence(
                    """
                    \(key) is not a property of a \(nodeType); it is a property of the component \
                    \(name(nodeID, in: document)) shows, which an override writes
                    """,
                    batch: """
                    write it as `{"op":"override","target":"\(address)","props":{"\(raw)":…}}`; \
                    the instance itself accepts \(properties(of: nodeID, in: document))
                    """,
                    command: """
                    run `woodcase override \(file) \(address) \(raw)=…` instead; the instance \
                    itself accepts \(properties(of: nodeID, in: document))
                    """,
                    in: dialect
                )
            }
            if let raw = preservedKey(key, on: nodeID, in: document) {
                let accepted = "\(name(nodeID, in: document)) accepts \(properties(of: nodeID, in: document))"
                return sentence(
                    preservedStatement(key, raw: raw, nodeType: nodeType),
                    batch: accepted,
                    command: accepted,
                    in: dialect
                )
            }
            return sentence(
                "\(key) is not a property of a \(nodeType)",
                batch: "\(name(nodeID, in: document)) accepts \(properties(of: nodeID, in: document))",
                command: "\(name(nodeID, in: document)) accepts \(properties(of: nodeID, in: document))",
                in: dialect
            )

        case let .propertyTypeMismatch(nodeID, key, expected, actual):
            return sentence(
                "\(key) on \(name(nodeID, in: document)) takes \(expected), but the value given is \(actual)",
                batch: "correct the value in `\"props\"`",
                // The accepted shape is already the first half of the sentence, and it
                // now carries a literal to paste; repeating it here doubled the message.
                command: "correct the value; `woodcase get \(file) \(nodeID)` shows what the node holds now",
                in: dialect
            )

        // MARK: Addressing

        case let .ambiguousAddress(address, candidates):
            return sentence(
                "\(address) matches \(candidates.count) nodes: \(list(candidates))",
                batch: byID(candidates),
                command: byID(candidates),
                in: dialect
            )

        case let .addressNotFound(address, nearMisses):
            // A miss the walk made *inside* an instance is answered with that
            // instance's own addresses, and with the rule that explains the miss.
            if nearMisses.contains(where: \.isInstanceDescendant) {
                let remedy = "address it as `\(nearMisses[0].path)`; a name path into an "
                    + "instance names every frame of the component's tree, and only an id "
                    + "may skip one"
                return sentence(
                    """
                    \(address) matches no node in this document; inside that instance the \
                    address is \(list(nearMisses))
                    """,
                    batch: remedy,
                    command: remedy,
                    in: dialect
                )
            }
            return sentence(
                nearMisses.isEmpty
                    ? "\(address) matches no node in this document"
                    : "\(address) matches no node in this document; nodes with that name: \(list(nearMisses))",
                batch: "check the path, or point it at the `@tag` of an earlier line that creates it",
                command: "run `woodcase tree \(file)` to list the addresses it has",
                in: dialect
            )

        // MARK: Consequences

        case let .componentHasInstances(componentID, instanceIDs):
            return sentence(
                """
                deleting \(name(componentID, in: document)) would leave \(instanceIDs.count) \
                \(instanceIDs.count == 1 ? "instance as a plain node" : "instances as plain nodes"): \
                \(list(instanceIDs.map { NodeAddressCandidate(id: $0, path: document.namePath(of: $0)) }))
                """,
                batch: "set `\"detach\": true` to detach them first",
                command: "pass `--detach` to detach them first",
                in: dialect
            )

        case let .componentTypeChange(componentID, from, to, instanceIDs):
            return sentence(
                """
                \(name(componentID, in: document)) is a reusable \(from) that \(instanceIDs.count) \
                \(instanceIDs.count == 1 ? "instance draws" : "instances draw"): \
                \(list(instanceIDs.map { NodeAddressCandidate(id: $0, path: document.namePath(of: $0)) })), \
                so its root cannot become a \(to)
                """,
                batch: """
                keep `"type": "\(from)"` on the replacement's root and rebuild what is under it
                """,
                command: """
                keep `"type": "\(from)"` on the replacement's root and rebuild what is under it
                """,
                in: dialect
            )

        case let .overrideTargetNotFound(refID, descendantKey, candidates):
            return sentence(
                """
                \(descendantKey) is not in the component \(name(refID, in: document)) instantiates; \
                it contains: \(list(candidates))
                """,
                batch: "address one of them as `\"\(refID)/<name>\"`",
                command: "address one of them — `woodcase override \(file) \(refID)/<name> key=value`",
                in: dialect
            )

        case let .overrideOnOwnSlotContent(refID, descendantKey, slotPath):
            return sentence(
                """
                \(refID)\(NodeAddress.separator)\(descendantKey) is a child this instance wrote into the \
                slot \(slotPath) itself; Pen ignores an override on it and draws it as written
                """,
                batch: """
                address the child instead — `{"op":"override","target":"\(refID)\(NodeAddress.separator)\
                \(descendantKey)",…}` — which writes the change onto it in the slot's children
                """,
                command: """
                address the child instead — `woodcase override \(file) \(refID)\(NodeAddress.separator)\
                \(descendantKey) key=value` — which writes the change onto it in the slot's children
                """,
                in: dialect
            )

        case let .overrideValueRejected(refID, descendantKey, key, expected, actual):
            let address = "\(refID)\(NodeAddress.separator)\(descendantKey)"
            return sentence(
                """
                \(key) on \(document.namePath(ofDescendant: descendantKey, in: refID)) takes \
                \(expected), but the value given is \(actual); an override a node cannot take \
                is dropped when the instance expands, so it is refused here instead
                """,
                batch: "correct the value in `\"props\"`",
                command: "correct the value; `woodcase get \(file) \(address)` shows what it draws now",
                in: dialect
            )

        case let .rootOverrideKeyReserved(refID, key, reason):
            let address = document.namePath(of: refID)
            let path = reason.propertyPath(for: key)
            return sentence(
                """
                \(key) on \(name(refID, in: document)) is \(reason.explanation), not a property \
                of the component it shows
                """,
                batch: reason.batchRemedy(address: address, path: path),
                command: reason.commandRemedy(file: file, address: address, path: path),
                in: dialect
            )

        case let .rootOverrideValueRejected(refID, key, expected, actual):
            return sentence(
                """
                \(key) on the component \(name(refID, in: document)) shows takes \(expected), but \
                the value given is \(actual); an override a node cannot take is dropped when the \
                instance expands, so it is refused here instead
                """,
                batch: "correct the value in `\"props\"`",
                command: "correct the value; `woodcase get \(file) \(refID) --expand` shows what it draws now",
                in: dialect
            )

        // MARK: Revisions

        case let .revisionConflict(nodeID, expected, actual):
            return sentence(
                """
                \(name(nodeID, in: document)) has changed: rev was \(expected), the node is now \(actual)
                """,
                batch: "re-read the node and rebuild this line with the current `rev`",
                command: "re-read it with `woodcase get \(file) \(nodeID)` and retry with the revision it prints",
                in: dialect
            )
        }
    }

    /// A node's .pen type name, or `"node"` when it is not in the document.
    private static func type(of nodeID: String, in document: EditableDocument) -> String {
        document.node(id: nodeID)?.kind.typeName ?? "node"
    }

    /// The property paths a node accepts, each backticked so the reader can paste one.
    private static func properties(of nodeID: String, in document: EditableDocument) -> String {
        guard let node = document.node(id: nodeID) else { return "nothing: it is not in this document" }
        return NodePropertyCodec.paths(for: node).map { "`\($0)`" }.joined(separator: ", ")
    }

    /// The raw .pen key a property path would be as a root override, or `nil`.
    ///
    /// Answers only for a `ref` — every other node's unknown property is simply
    /// unknown — and only for a key the component's own root would accept, so a plain
    /// typo keeps the plain message.
    private static func rootOverrideKey(
        _ path: String,
        on nodeID: String,
        in document: EditableDocument
    ) -> String? {
        guard case .ref = document.node(id: nodeID)?.kind,
              let root = document.componentRoot(ofInstance: nodeID)
        else { return nil }
        let raw = NodePropertyCodec.rawKey(for: path)
        guard RootOverrideRefusal.refusing(raw) == nil,
              NodePropertyCodec.rawKeys(acceptedBy: root).contains(raw)
        else { return nil }
        return raw
    }

    /// The remedy for an address that matched more than one node.
    private static func byID(_ candidates: [NodeAddressCandidate]) -> String {
        guard let first = candidates.first else { return "address it by id to say which" }
        return "address it by id to say which, as `\(NodeAddress.marker(forID: first.id))`"
    }
}
