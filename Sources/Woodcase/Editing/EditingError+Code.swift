//
//  EditingError+Code.swift
//  Woodcase
//

import Foundation

public extension EditingError {
    /// A stable machine-readable name for the failure family: the case's own name.
    ///
    /// The sentence a refusal carries is written for a person and may be reworded; this
    /// is the token a program branches on, and it does not move. A script catches a
    /// `WoodcaseError` and reads `err.code`; a `--json` report carries the same string.
    ///
    /// ```swift
    /// EditingError.ambiguousAddress(address: "Title", candidates: []).code // "ambiguousAddress"
    /// ```
    ///
    /// Spelled out rather than derived from reflection: `Mirror` gives the label of a
    /// case *with* associated values but nothing for one without, so half the vocabulary
    /// would be missing and the other half would move if a payload were ever added.
    var code: String {
        switch self {
        case .nodeNotFound: "nodeNotFound"
        case .duplicateNodeID: "duplicateNodeID"
        case .invalidNodeID: "invalidNodeID"
        case .parentNotFound: "parentNotFound"
        case .cannotHaveChildren: "cannotHaveChildren"
        case .invalidIndex: "invalidIndex"
        case .wouldCreateCycle: "wouldCreateCycle"
        case .variableNotFound: "variableNotFound"
        case .variableAlreadyExists: "variableAlreadyExists"
        case .importNotFound: "importNotFound"
        case .importAlreadyExists: "importAlreadyExists"
        case .themeAxisNotFound: "themeAxisNotFound"
        case .themeAxisAlreadyExists: "themeAxisAlreadyExists"
        case .notARefNode: "notARefNode"
        case .unknownProperty: "unknownProperty"
        case .propertyTypeMismatch: "propertyTypeMismatch"
        case .ambiguousAddress: "ambiguousAddress"
        case .addressNotFound: "addressNotFound"
        case .componentHasInstances: "componentHasInstances"
        case .componentTypeChange: "componentTypeChange"
        case .overrideTargetNotFound: "overrideTargetNotFound"
        case .overrideOnOwnSlotContent: "overrideOnOwnSlotContent"
        case .overrideValueRejected: "overrideValueRejected"
        case .rootOverrideKeyReserved: "rootOverrideKeyReserved"
        case .rootOverrideValueRejected: "rootOverrideValueRejected"
        case .revisionConflict: "revisionConflict"
        }
    }

    /// The nodes the failure names, where it names any: the candidates of an ambiguous
    /// address, the near misses of a missing one, the targets an override could have
    /// meant.
    ///
    /// The list a sentence spells out in prose, as values, so a caller can act on it
    /// without parsing the prose. Empty for every case that names none.
    var candidates: [NodeAddressCandidate] {
        switch self {
        case let .ambiguousAddress(_, candidates): candidates
        case let .addressNotFound(_, nearMisses): nearMisses
        case let .overrideTargetNotFound(_, _, candidates): candidates
        default: []
        }
    }
}
