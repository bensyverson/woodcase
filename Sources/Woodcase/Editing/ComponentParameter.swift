//
//  ComponentParameter.swift
//  Woodcase
//

import Foundation

/// One parameter a component publishes, declared in `common.metadata._props`.
///
/// The declaration is codegen's, and has been since components were first emitted:
/// `{"label": "Body/Title"}` on a reusable node's metadata means "the parameter
/// `label` is the content of the node at `Body/Title`". ``ComponentAnalyzer`` reads it
/// to type a generated component's props; this is the same reading, resolved against
/// an ``EditableDocument``, so a *name* a component publishes is a key the editing
/// verbs accept. Nothing new enters the .pen format.
///
/// ```swift
/// document.parameters(ofComponent: "Stc01")
/// // [ComponentParameter(name: "label", path: "Body/Title",
/// //                     nodeID: "Ttl01", property: "kind.content", type: .string)]
/// ```
///
/// A declaration that resolves to nothing is still reported — with ``nodeID`` and
/// ``property`` `nil` — because a parameter that names a node the component no longer
/// has is exactly what a caller needs told, and silence would read as "no such
/// parameter".
public struct ComponentParameter: Friendly {
    /// Creates a parameter.
    ///
    /// - Parameters:
    ///   - name: The name the component publishes.
    ///   - path: The declared name path, from the component root.
    ///   - nodeID: The descendant the path resolves to, or `nil`.
    ///   - property: The property path the value is written to, or `nil`.
    ///   - type: The type codegen infers for the parameter, or `nil`.
    ///   - collidesWithProperty: Whether the component root already has a property of
    ///     this name.
    public init(
        name: String,
        path: String,
        nodeID: String? = nil,
        property: String? = nil,
        type: PropType? = nil,
        collidesWithProperty: Bool = false
    ) {
        self.name = name
        self.path = path
        self.nodeID = nodeID
        self.property = property
        self.type = type
        self.collidesWithProperty = collidesWithProperty
    }

    /// The name the component publishes, and a caller writes as a key.
    public var name: String

    /// The declared name path to the descendant, from the component root — `Body/Title`.
    public var path: String

    /// The id of the descendant the path names, or `nil` when it names nothing.
    public var nodeID: String?

    /// The property path the parameter's value is written to — `kind.content` for a
    /// text node, `kind.fills` for a shape — or `nil` when the target has no such
    /// property.
    public var property: String?

    /// The type codegen infers for this parameter, or `nil` when nothing resolved.
    public var type: PropType?

    /// Whether the component root already has a property of this name.
    ///
    /// The raw property wins: `width=320` on an instance means the instance's width,
    /// whatever a parameter of the same name would like it to mean. A verb that
    /// resolves a key says so rather than choosing quietly.
    public var collidesWithProperty: Bool

    /// The key a `cp` writes to reach this parameter's node the long way —
    /// `Body/Title/kind.content` — or `nil` when the parameter resolves to nothing.
    ///
    /// This is what a report prints beside the name: the address that means the same
    /// thing, so a reader who wants to see the mechanism can.
    public var address: String? {
        property.map { "\(path)\(NodeAddress.separator)\($0)" }
    }

    /// The property path a parameter's value is written to on a node of this kind.
    ///
    /// The mirror of ``ComponentAnalyzer``'s own type inference: it reads a text node's
    /// content and a shape's fills, and nothing else, so those are the two properties a
    /// declared name can mean. A kind with neither has no property a bare parameter
    /// name could write, and the parameter is reported unresolved rather than guessed
    /// at.
    ///
    /// - Parameter kind: The target node's kind.
    /// - Returns: The property path, or `nil` for a kind codegen reads nothing from.
    public static func property(of kind: PenNode.Kind) -> String? {
        switch kind {
        case .text: "kind.content"
        case .rectangle, .frame, .ellipse: "kind.fills"
        default: nil
        }
    }
}
