//
//  SwiftUIComponentScope.swift
//  Woodcase
//

/// What the node emitter knows about components while it writes one file: every component
/// the module declares, every reusable node an instance can name, the props of the
/// component whose body it is writing, and the components already being drawn above it.
struct SwiftUIComponentScope: Friendly {
    /// The components the module declares a view struct for, by component id.
    var components: [String: SwiftUIComponent] = [:]

    /// Every reusable node in the document, by id: what an instance is inlined from, which
    /// includes reusable nodes that are no analyzed component (a state variant).
    var reusable: [String: PenNode] = [:]

    /// The props of the component whose body is being written, by the id of the node each
    /// is read at; empty in a page and in an inlined copy.
    var bound: [String: [SwiftUIProp]] = [:]

    /// The slots of the component whose body is being written, by the id of the frame
    /// each is drawn in; empty in a page and in an inlined copy.
    var slots: [String: SwiftUISlot] = [:]

    /// The document's theme, which views read variables through; `nil` when the document has
    /// neither themes nor variables.
    var theme: SwiftUITheme?

    /// The component ids on the way down to the node being written, so an instance of a
    /// component inside itself is caught rather than inlined forever.
    var chain: Set<String> = []

    /// The id of the text node drawn as the component's `TextField`, in a text input's
    /// body; `nil` everywhere else.
    var textField: String?

    /// A scope with no components, for a page of a document without any.
    init() {}

    /// The scope of a module of `components`, named by `typeNames`, over `document`'s
    /// reusable nodes, reading variables through `theme`.
    init(document: PenDocument, components: [ComponentDefinition], typeNames: [String: String], theme: SwiftUITheme? = nil) {
        reusable = PenRefExpander.buildRegistry(from: document.children)
        self.theme = theme
        for definition in components {
            let name = typeNames[definition.id] ?? definition.name
            self.components[definition.id] = SwiftUIComponent(definition, typeName: name, theme: theme)
        }
    }

    /// This scope inside `component`'s body: its props and slots bound, it on the chain.
    func drawing(_ component: SwiftUIComponent) -> Self {
        var scope = self
        scope.bound = component.propsByNodeID
        scope.slots = component.slotsByNodeID
        scope.chain = [component.definition.id]
        return scope
    }

    /// This scope inside an inlined copy: no props or slots bound, `chain` on the way down.
    func inlining(chain: Set<String>) -> Self {
        var scope = self
        scope.bound = [:]
        scope.slots = [:]
        scope.chain = chain
        scope.textField = nil
        return scope
    }

    /// The prop of `kind` read at the node `nodeID`, if the body binds one there.
    func prop(_ kind: SwiftUIProp.Kind, at nodeID: String) -> SwiftUIProp? {
        bound[nodeID]?.first { $0.kind == kind }
    }
}
