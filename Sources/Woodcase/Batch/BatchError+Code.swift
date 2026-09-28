//
//  BatchError+Code.swift
//  Woodcase
//

import Foundation

public extension BatchError {
    /// A stable machine-readable name for the failure family: the case's own name.
    ///
    /// The counterpart of ``EditingError/code``, and it follows the same rule for the
    /// same reason: the sentence is written for a person and may be reworded, while this
    /// is the token a program branches on. A script catches a `WoodcaseError` and reads
    /// `err.code` without caring which of the two enums raised it.
    ///
    /// ```swift
    /// BatchError.setInsideInstance(address: "Orders/Value", instancePath: "Orders").code
    /// // "setInsideInstance"
    /// ```
    ///
    /// ``documentRevisionConflict(expected:actual:)`` keeps its own name rather than
    /// borrowing ``EditingError/revisionConflict(nodeID:expected:actual:)``'s: the two
    /// are guarding different things — one node against the whole document — and a
    /// caller that has to re-read before retrying needs to know which it was.
    ///
    /// Spelled out rather than derived from reflection, for ``EditingError/code``'s
    /// reason: `Mirror` names a case with associated values and says nothing about one
    /// without, so half the vocabulary would be missing and the other half would move
    /// the day a payload were added.
    var code: String {
        switch self {
        case .malformedLine: "malformedLine"
        case .malformedRow: "malformedRow"
        case .copyPathNotInSource: "copyPathNotInSource"
        case .parameterPathNotFound: "parameterPathNotFound"
        case .emptyCopyRows: "emptyCopyRows"
        case .copyTagWithRows: "copyTagWithRows"
        case .unnamedNode: "unnamedNode"
        case .literalRootOverridesKey: "literalRootOverridesKey"
        case .replacementIDMismatch: "replacementIDMismatch"
        case .setInsideInstance: "setInsideInstance"
        case .structureInsideSlot: "structureInsideSlot"
        case .overrideOutsideInstance: "overrideOutsideInstance"
        case .overrideWithoutProperties: "overrideWithoutProperties"
        case .parentInsideInstance: "parentInsideInstance"
        case .documentRevisionConflict: "documentRevisionConflict"
        case .guardConflict: "guardConflict"
        case .guardNodeMissing: "guardNodeMissing"
        case .guardOnTag: "guardOnTag"
        case .guardWithoutTarget: "guardWithoutTarget"
        }
    }
}
