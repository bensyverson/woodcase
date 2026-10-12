//
//  EditableDocument+VariableLookup.swift
//  Woodcase
//

import Foundation

/// Which variable a `$name` reference names, as a writer judges a binding.
///
/// A reference resolves against the document's own variables first and then the ones
/// its imports contribute (`$alias:name`, from libraries read with the document). An
/// imported name whose library was not read cannot be judged either way, so it is
/// reported as possibly defined rather than as missing.
extension EditableDocument {
    /// The variable a reference names: the document's own, or an imported one.
    ///
    /// - Parameter name: The name, without `$` — `brand`, or `lib:accent`.
    /// - Returns: The variable, or `nil` when neither the document nor a library read
    ///   with it defines one.
    func variable(named name: String) -> PenVariable? {
        variables?[name] ?? importedStore.definitions.variables[name]
    }

    /// The variables the document's imports contribute, keyed `alias:name`.
    var importedVariables: [String: PenVariable] {
        importedStore.definitions.variables
    }

    /// Whether `name` is an imported variable whose library was not read with the
    /// document, so whether it exists cannot be known.
    ///
    /// - Parameter name: The name, without `$`.
    /// - Returns: `true` for `alias:rest` where the document imports `alias` and the
    ///   library at its path was not read.
    func mayDefineImported(_ name: String) -> Bool {
        guard let separator = name.firstIndex(of: Self.importSeparator),
              let path = imports?[String(name[..<separator])]
        else { return false }
        return readContext.libraries.documents[path] == nil
    }

    /// What joins an import alias to the name of a variable it contributes.
    static let importSeparator: Character = ":"
}
