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
                message: message, errorCode: editing.code
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
        case .duplicateNodeID, .invalidNodeID, .parentNotFound, .cannotHaveChildren, .invalidIndex,
             .wouldCreateCycle, .variableNotFound, .variableAlreadyExists, .importNotFound,
             .importAlreadyExists, .themeAxisNotFound, .themeAxisAlreadyExists, .notARefNode,
             .unknownDocumentProperty, .documentPropertyTypeMismatch, .componentHasInstances,
             .componentTypeChange, .overrideOnOwnSlotContent, .revisionConflict,
             .wouldCloseComponentLoop:
            (.documentRefused, nil, nil)
        }
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
