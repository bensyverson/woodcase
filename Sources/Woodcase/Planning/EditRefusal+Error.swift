//
//  EditRefusal+Error.swift
//  Woodcase
//

import Foundation

extension EditRefusal {
    /// The refusal an error raised while planning stands for.
    ///
    /// The planner's core raises the document's and the grammar's own errors, because the
    /// batch applier — and so every CLI verb — keys its messages and exit codes by them.
    /// This is the one place they become ``Code``s, so an editor branches on the same
    /// families whichever layer refused. The sentence is
    /// ``BatchErrorMessage/describe(_:in:dialect:)``'s, in batch dialect.
    ///
    /// - Parameters:
    ///   - error: What planning threw.
    ///   - address: The address as written.
    ///   - document: The document, for name paths in the sentence.
    init(_ error: any Error, address: String, in document: EditableDocument) {
        if let refusal = error as? EditRefusal {
            self = refusal
            return
        }
        let message = BatchErrorMessage.describe(error, in: document)
        if let editing = error as? EditingError {
            let (code, property, expected) = Self.classify(editing)
            self.init(
                code: code, address: address, property: property, expected: expected,
                suggestion: Self.suggestion(for: editing),
                message: message, errorCode: editing.code, detail: Self.detail(of: editing, in: document)
            )
        } else if let batch = error as? BatchError {
            self.init(
                code: Self.classify(batch), address: address, suggestion: Self.suggestion(for: batch),
                message: message, errorCode: batch.code
            )
        } else {
            self.init(code: .documentRefused, address: address, message: message)
        }
    }

    // MARK: - Private

    /// The family, refused property and expected form an ``EditingError`` carries.
    private static func classify(_ error: EditingError) -> (Code, String?, String?) {
        switch error {
        case .addressNotFound, .nodeNotFound: (.addressNotFound, nil, nil)
        case .ambiguousAddress: (.ambiguousAddress, nil, nil)
        case .overrideTargetNotFound: (.overrideTargetNotFound, nil, nil)
        case let .unknownProperty(_, key, _): (.unknownProperty, key, nil)
        case let .propertyTypeMismatch(_, key, expected, _): (.invalidForm, key, expected)
        case let .overrideValueRejected(_, _, key, expected, _): (.invalidForm, key, expected)
        case let .rootOverrideValueRejected(_, key, expected, _): (.invalidForm, key, expected)
        case let .postItMetadataRejected(_, key, _, accepted, _):
            (.invalidForm, key, accepted.joined(separator: " | "))
        case .textSpansRejected: (.invalidForm, NodePropertyCodec.metadataPath, nil)
        case let .rootOverrideKeyReserved(_, key, _): (.reservedOverrideKey, key, nil)
        case .wouldCreateCycle: (.wouldCreateCycle, nil, nil)
        case .wouldCloseComponentLoop: (.wouldCloseComponentLoop, nil, nil)
        case .componentHasInstances: (.componentHasInstances, nil, nil)
        case .componentTypeChange: (.componentTypeChange, nil, nil)
        case .duplicateNodeID, .invalidNodeID, .parentNotFound, .cannotHaveChildren, .invalidIndex,
             .variableNotFound, .variableAlreadyExists, .importNotFound,
             .importAlreadyExists, .themeAxisNotFound, .themeAxisAlreadyExists, .notARefNode,
             .unknownDocumentProperty, .documentPropertyTypeMismatch,
             .overrideOnOwnSlotContent, .revisionConflict:
            (.documentRefused, nil, nil)
        case let .storedAtNaturalPath(_, path, _): (.storedAtNaturalPath, path, nil)
        }
    }

    /// What an ``EditingError`` names, as a ``Detail``; `nil` for one that names nothing
    /// beyond the address and property.
    ///
    /// A loop's path comes closed (`["Card", "Badge", "Card"]`); the detail drops the
    /// repeated first component and names each by its `name`, or its id when it has none.
    private static func detail(of error: EditingError, in document: EditableDocument) -> Detail? {
        switch error {
        case let .wouldCloseComponentLoop(path):
            let cycle = path.count > 1 && path.first == path.last ? path.dropLast() : path[...]
            return .componentLoop(ComponentLoop(members: cycle.map { id in
                ComponentLoop.Member(id: id, name: document.node(id: id)?.common.name ?? id)
            }))
        case let .componentHasInstances(componentID, instanceIDs):
            return .componentHasInstances(componentID: componentID, instanceIDs: instanceIDs)
        case let .componentTypeChange(componentID, from, to, instanceIDs):
            return .componentTypeChange(componentID: componentID, from: from, to: to, instanceIDs: instanceIDs)
        case let .wouldCreateCycle(nodeID, targetParentID):
            return .wouldCreateCycle(nodeID: nodeID, targetParentID: targetParentID)
        case let .ambiguousAddress(_, candidates), let .addressNotFound(_, candidates),
             let .overrideTargetNotFound(_, _, candidates):
            return candidates.isEmpty ? nil : .candidates(candidates)
        case .nodeNotFound, .duplicateNodeID, .invalidNodeID, .parentNotFound, .cannotHaveChildren,
             .invalidIndex, .variableNotFound, .variableAlreadyExists, .importNotFound,
             .importAlreadyExists, .themeAxisNotFound, .themeAxisAlreadyExists, .notARefNode,
             .unknownProperty, .propertyTypeMismatch, .unknownDocumentProperty,
             .documentPropertyTypeMismatch, .postItMetadataRejected, .textSpansRejected,
             .overrideOnOwnSlotContent, .overrideValueRejected, .rootOverrideKeyReserved,
             .rootOverrideValueRejected, .revisionConflict, .storedAtNaturalPath:
            return nil
        }
    }

    /// The write to make instead of a storage path: the natural path, its value to fill in.
    private static func suggestion(for error: EditingError) -> String? {
        guard case let .storedAtNaturalPath(_, _, naturalPath) = error else { return nil }
        return "\(naturalPath)=…"
    }

    /// The write that would have been accepted instead: for a set inside an instance,
    /// the override's `key=value` assignments.
    private static func suggestion(for error: BatchError) -> String? {
        guard case let .setInsideInstance(_, _, properties) = error, !properties.isEmpty else { return nil }
        return BatchErrorMessage.overrideAssignments(properties).joined(separator: " ")
    }

    /// The family a ``BatchError`` belongs to.
    private static func classify(_ error: BatchError) -> Code {
        switch error {
        case .overrideOutsideInstance: .overrideOutsideInstance
        case .setInsideInstance: .setInsideInstance
        case .overrideWithoutProperties: .noProperties
        case .parameterPathNotFound: .parameterPathNotFound
        case .malformedLine, .malformedRow, .copyPathNotInSource, .emptyCopyRows, .copyTagWithRows,
             .unnamedNode, .literalRootOverridesKey, .replacementIDMismatch, .structureInsideSlot,
             .parentInsideInstance, .documentRevisionConflict, .guardConflict, .guardNodeMissing,
             .guardOnTag, .guardWithoutTarget:
            .documentRefused
        }
    }
}
