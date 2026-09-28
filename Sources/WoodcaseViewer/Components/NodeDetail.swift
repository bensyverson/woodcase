//
//  NodeDetail.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One property of the selected node: what it is called, what it is worth, and where
/// that worth came from.
///
/// The three origins are the three ways a value gets onto a rendered node, and telling
/// them apart is the whole point of the pane. A *literal* is written on the node. A
/// *variable* is written as `$name` and is worth whatever the theme says today — change
/// the theme and the value moves. An *override* was written on the component instance
/// this node sits inside, not on the node at all, so the command that changes it names
/// the instance and the definition it departs from is still there underneath.
public struct NodeDetail: Friendly, Identifiable {
    /// Where a value came from.
    public enum Origin: String, Friendly {
        /// Written on the node, as it stands.
        case literal
        /// Written as `$name`; the value shown is what the current theme resolves it to.
        case variable
        /// Written on the instance this node sits inside, over the definition's value.
        case override
    }

    /// The instance an overridden value came from, and what it replaced.
    public struct Source: Friendly {
        /// Creates a source.
        ///
        /// - Parameters:
        ///   - instance: The id of the `ref` node whose `descendants` map carries the
        ///     override — the outermost instance, which is where a write goes.
        ///   - path: That instance's name path, for a reader.
        ///   - was: The definition's own value, as text.
        public init(instance: String, path: String, was: String) {
            self.instance = instance
            self.path = path
            self.was = was
        }

        /// The id of the instance the override is stored on.
        public let instance: String

        /// That instance's name path.
        public let path: String

        /// What the component definition says, underneath the override.
        public let was: String
    }

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - path: The codec path — `common.name`, `kind.fills` — which is what `set`
    ///     and `get` name the property by.
    ///   - key: The raw key the .pen file writes, beside it.
    ///   - value: The value as it renders under the current theme.
    ///   - origin: Where that value came from.
    ///   - variables: The variables the authored value names, sorted, empty when none.
    ///   - source: The instance an override came from, when ``origin`` is
    ///     ``Origin/override``.
    public init(
        path: String,
        key: String,
        value: String,
        origin: Origin,
        variables: [String] = [],
        source: Source? = nil
    ) {
        self.path = path
        self.key = key
        self.value = value
        self.origin = origin
        self.variables = variables
        self.source = source
    }

    /// The codec path, which is also this row's id in the pane.
    public var id: String {
        path
    }

    /// The codec path — what `woodcase set` and `woodcase get` name it by.
    public let path: String

    /// The raw key the .pen file writes.
    public let key: String

    /// The value as it renders under the current theme.
    public let value: String

    /// Where that value came from.
    public let origin: Origin

    /// The variables the authored value names, sorted.
    ///
    /// Usually one, and one is why the row is marked ``Origin/variable``. It is a list
    /// because a fill or an effect can bind several at once, and naming only the first
    /// would hide the rest.
    public let variables: [String]

    /// The instance an overridden value came from.
    public let source: Source?

    /// The variables written as a reader refers to them — `$accent`.
    public var variableLabel: String {
        variables.map { "$\($0)" }.joined(separator: ", ")
    }

    /// The word on the row's mark.
    public var originLabel: String {
        switch origin {
        case .literal: "literal"
        case .variable: variableLabel
        case .override: "override"
        }
    }
}
