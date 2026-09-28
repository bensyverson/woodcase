//
//  PenNode+Editing.swift
//  Woodcase
//

import Foundation

public extension PenNode.Kind {
    /// Returns a copy of this kind with children set to `nil`.
    ///
    /// Only affects `.frame` and `.group` — all other kinds are returned unchanged.
    func withEmptyChildren() -> PenNode.Kind {
        switch self {
        case var .frame(data):
            data.children = nil
            return .frame(data)
        case var .group(data):
            data.children = nil
            return .group(data)
        default:
            return self
        }
    }

    /// Returns a copy of this kind with children replaced by the given array.
    ///
    /// Only affects `.frame` and `.group` — all other kinds are returned unchanged.
    /// - Parameter children: The new children to set, or `nil` to clear.
    func withChildren(_ children: [PenNode]?) -> PenNode.Kind {
        switch self {
        case var .frame(data):
            data.children = children
            return .frame(data)
        case var .group(data):
            data.children = children
            return .group(data)
        default:
            return self
        }
    }

    /// Whether this kind supports child nodes.
    ///
    /// Only `.frame` and `.group` can have children in the .pen format.
    var canHaveChildren: Bool {
        switch self {
        case .frame, .group:
            true
        default:
            false
        }
    }

    /// The .pen type name string for this kind (e.g. "frame", "text", "rectangle").
    var typeName: String {
        switch self {
        case .frame: "frame"
        case .text: "text"
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .path: "path"
        case .group: "group"
        case .line: "line"
        case .polygon: "polygon"
        case .ref: "ref"
        case .note: "note"
        case .prompt: "prompt"
        case .context: "context"
        case .icon: "icon"
        case .script: "script"
        case .browser: "browser"
        case .connection: "connection"
        case let .unknown(typeName, _): typeName
        }
    }

    /// The inline child nodes this kind carries, if any.
    ///
    /// Empty for a leaf kind and for a container whose `children` is `nil` — which is
    /// every node in the flat store, where children live in ``EditableDocument/children``.
    /// A consumer that walks an expanded document — the viewer's overlay, which
    /// accumulates parent origins the way the renderer's transform stack does — reads
    /// children through this rather than writing the two-case switch a second time.
    var inlineChildren: [PenNode] {
        switch self {
        case let .frame(data):
            data.children ?? []
        case let .group(data):
            data.children ?? []
        default:
            []
        }
    }

    /// Returns the IDs of inline children, if any.
    ///
    /// Used during flattening to extract child IDs before stripping children.
    /// Returns an empty array for leaf nodes or containers with `nil` children.
    var childIDs: [String] {
        declaredChildIDs ?? []
    }

    /// The ids of the children this kind *declares*, or `nil` when it declares none.
    ///
    /// The distinction ``childIDs`` flattens is the one the .pen file keeps: a container
    /// written `"children": []` declares an empty list, and one written without the key
    /// declares nothing. Both hold no children, and only this tells them apart — so
    /// every writer into ``EditableDocument/children`` reads its entry from here, and a
    /// node round-trips to the bytes it arrived as rather than to an equivalent tree.
    var declaredChildIDs: [String]? {
        switch self {
        case let .frame(data):
            data.children?.map(\.id)
        case let .group(data):
            data.children?.map(\.id)
        default:
            nil
        }
    }
}
