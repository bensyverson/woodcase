//
//  EditableDocument+Parameters.swift
//  Woodcase
//

import Foundation

/// Reading a component's published parameter list off its `common.metadata._props`.
///
/// One reading, used by every verb that has to turn a published name into a write:
/// `override`, `cp`, and the `get` that prints the list. ``ComponentAnalyzer`` reads
/// the same declaration off a nested ``PenNode`` tree for code generation; this reads
/// it off the flat store, by the same rule — segments are consecutive parent→child
/// steps matched on `common.name`, first match wins.
public extension EditableDocument {
    /// The parameters a node publishes.
    ///
    /// - Parameter id: The component's node id. A node that declares nothing — or is
    ///   not reusable at all — publishes none.
    /// - Returns: The declared parameters, sorted by name, resolved where they resolve.
    func parameters(ofComponent id: String) -> [ComponentParameter] {
        guard let root = node(id: id),
              let metadata = root.common.metadata,
              case let .dictionary(declared) = metadata[Self.parametersKey]
        else { return [] }
        let claimed = NodePropertyCodec.rawKeys(acceptedBy: root)
        return declared
            .compactMap { name, value -> ComponentParameter? in
                guard case let .string(path) = value else { return nil }
                return parameter(
                    named: name, at: path, under: id, claimed: claimed.contains(name)
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// The parameter a key names on a component, if it names one.
    ///
    /// - Parameters:
    ///   - name: The key as written.
    ///   - id: The component's node id.
    /// - Returns: The parameter, or `nil` when the component publishes no such name.
    func parameter(named name: String, ofComponent id: String) -> ComponentParameter? {
        parameters(ofComponent: id).first { $0.name == name }
    }

    /// The descendant a name path names inside a subtree of the flat store.
    ///
    /// - Parameters:
    ///   - path: A `/`-separated path of names, from `rootID` down, not including it.
    ///   - rootID: Where the walk starts.
    /// - Returns: The id of the node the path names, or `nil` when a segment matches
    ///   no child.
    func descendantID(atNamePath path: String, under rootID: String) -> String? {
        var current = rootID
        let segments = path.split(separator: NodeAddress.separator).map(String.init)
        guard !segments.isEmpty else { return nil }
        for segment in segments {
            guard let next = childIDs(of: current).first(where: { node(id: $0)?.common.name == segment })
            else { return nil }
            current = next
        }
        return current
    }

    // MARK: - Private

    /// The metadata key a component's parameter list is declared under.
    private static var parametersKey: String {
        "_props"
    }

    /// One declaration, resolved as far as the document allows.
    private func parameter(
        named name: String,
        at path: String,
        under id: String,
        claimed: Bool
    ) -> ComponentParameter {
        guard let targetID = descendantID(atNamePath: path, under: id),
              let target = node(id: targetID),
              let property = ComponentParameter.property(of: target.kind)
        else {
            return ComponentParameter(
                name: name, path: path, collidesWithProperty: claimed
            )
        }
        return ComponentParameter(
            name: name,
            path: path,
            nodeID: targetID,
            property: property,
            type: ComponentAnalyzer.inferPropType(from: target).type,
            collidesWithProperty: claimed
        )
    }
}
