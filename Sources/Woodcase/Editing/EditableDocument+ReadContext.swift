//
//  EditableDocument+ReadContext.swift
//  Woodcase
//

import Foundation
import Synchronization

public extension EditableDocument {
    /// What the document was read with — its libraries and the font resolver it settles
    /// through. Never written back; see ``PenReadContext``.
    ///
    /// Setting it drops every cached expansion and layout, since both depend on which
    /// imported components exist.
    var readContext: PenReadContext {
        get { _readContext }
        set {
            _readContext = newValue
            _readContextSerial = Self.nextReadContextSerial()
            _importCache = nil
            _expansionCache?.invalidateAll()
            _layoutCache?.invalidateAll()
        }
    }

    /// The components, variables and theme axes the document's imports contribute
    /// from the libraries it was read with.
    var importedDefinitions: PenImportedDefinitions {
        importedStore.definitions
    }

    /// The document as materialized, with the imported variables and theme axes merged
    /// in — the form every resolution of it starts from. Its tree and its `imports`
    /// are exactly ``materialize()``'s.
    ///
    /// - Returns: The document, able to resolve `$V:name` and pin `V:axis`.
    func materializeWithImports() -> PenDocument {
        importedDefinitions.merged(into: materialize())
    }

    /// The document as code generation reads it: materialized, with the components,
    /// variables and theme axes of every library it imports merged in, each imported
    /// component a root beside the file's own.
    ///
    /// ``PenImportResolver/resolve(_:libraries:)`` over ``materialize()`` and the
    /// libraries in ``readContext`` — the one merge `woodcase generate` and the viewer's
    /// code panel share, so the panel shows the code the verb writes. Unlike every canvas
    /// read (``expanded(for:)``), an imported definition *is* a root here, because
    /// generation turns every component into code.
    ///
    /// - Returns: The document with its imports resolved and its `imports` cleared.
    func materializeForGeneration() -> PenDocument {
        PenImportResolver.resolve(materialize(), libraries: readContext.libraries.documents)
    }

    /// The document with every `ref` expanded, imported instances included.
    ///
    /// This is the one expansion every reader shares — ``SettledTree``, ``NodeLookup``,
    /// `shot`, `render`, the viewer — so an instance of `V:Button` settles to the same
    /// rect wherever it is asked about.
    ///
    /// - Parameter purpose: What the output is for; see ``PenRefExpander/Purpose``.
    /// - Returns: The expanded document. No imported definition is ever one of its roots.
    func expanded(for purpose: PenRefExpander.Purpose) -> PenDocument {
        PenRefExpander.expand(materializeWithImports(), for: purpose, imported: importedStore.expansionRegistry)
    }
}

extension EditableDocument {
    /// The serial of the last document or read context made in this process.
    private static let readContextSerials = Atomic<Int>(0)

    /// Draws a serial no document or read context has had before.
    ///
    /// - Returns: The serial.
    static func nextReadContextSerial() -> Int {
        readContextSerials.add(1, ordering: .relaxed).newValue
    }

    /// The imported definitions, flattened, for the document's current `imports` and
    /// the libraries it was read with. Built on first use and whenever `imports` has
    /// changed since.
    var importedStore: ImportedComponentStore {
        if let cached = _importCache, cached.imports == imports { return cached }
        let store = ImportedComponentStore(
            imports: imports,
            definitions: PenImportResolver.definitions(
                for: imports, libraries: _readContext.libraries.documents
            )
        )
        _importCache = store
        return store
    }
}
