//
//  BatchOperation+Ops.swift
//  Woodcase
//

import Foundation

public extension BatchOperation {
    /// `{"op":"set","target":…,"props":{…},"rev":…}` — patch properties on one node.
    ///
    /// Keys in `props` come from ``NodePropertyCodec/paths(for:)`` — the
    /// `"common.name"` / `"kind.width"` vocabulary — and values are in the .pen
    /// file's own JSON shape. `rev` guards `target`.
    struct SetOp: Friendly {
        /// Creates a set operation.
        ///
        /// - Parameters:
        ///   - target: The node to patch.
        ///   - props: Properties to set, keyed by property path.
        ///   - rev: The revision of `target` the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            target: NodeAddress,
            props: [String: AnyCodable],
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.target = target
            self.props = props
            self.rev = rev
            self.guards = guards
        }

        /// The node to patch.
        public var target: NodeAddress
        /// Properties to set, keyed by ``NodePropertyCodec`` path.
        public var props: [String: AnyCodable]
        /// The revision of `target` the caller last observed.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"add","parent":…,"node":{…},"at":N,"tag":…,"rev":…}` — insert a new subtree.
    ///
    /// Omitting `parent` inserts at the document root. Ids in `node` are
    /// optional and are replaced with fresh ones either way, so the caller
    /// never has to invent an id it will not keep. Every node in the subtree
    /// must carry a `name`. `rev` guards `parent`, or the whole document when
    /// there is none.
    struct AddOp: Friendly {
        /// Creates an add operation.
        ///
        /// - Parameters:
        ///   - node: The subtree to insert.
        ///   - parent: The container to insert into, or `nil` for the document root.
        ///   - at: The position among the parent's children, or `nil` to append.
        ///   - tag: A batch tag later lines can address as `@tag`.
        ///   - rev: The revision of `parent` — or of the document — the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            node: PenNode,
            parent: NodeAddress? = nil,
            at: Int? = nil,
            tag: String? = nil,
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.node = node
            self.parent = parent
            self.at = at
            self.tag = tag
            self.rev = rev
            self.guards = guards
        }

        /// The subtree to insert.
        public var node: PenNode
        /// The container to insert into, or `nil` for the document root.
        public var parent: NodeAddress?
        /// The position among the parent's children, or `nil` to append.
        public var at: Int?
        /// A batch tag later lines can address as `@tag`.
        public var tag: String?
        /// The revision of `parent` — or of the document — the caller last observed.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"replace","target":…,"node":{…},"rev":…}` — swap a node's subtree in place.
    ///
    /// The node keeps its id, its parent and its index among its siblings; everything
    /// under it is replaced. Ids inside `node` follow the same rule as ``AddOp``'s —
    /// one you write is kept, one you leave out is generated — with the addition that
    /// an id the *replaced* subtree currently holds is free to reuse. `node`'s own
    /// `id`, if written, must be the target's: it is kept either way, and a different
    /// one is refused rather than silently ignored. `rev` guards `target`.
    struct ReplaceOp: Friendly {
        /// Creates a replace operation.
        ///
        /// - Parameters:
        ///   - target: The node whose subtree is being swapped.
        ///   - node: The subtree that takes its place.
        ///   - rev: The revision of `target` the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            target: NodeAddress,
            node: PenNode,
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.target = target
            self.node = node
            self.rev = rev
            self.guards = guards
        }

        /// The node whose subtree is being swapped.
        public var target: NodeAddress
        /// The subtree that takes its place.
        public var node: PenNode
        /// The revision of `target` the caller last observed.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"cp","source":…,"parent":…,"at":N,"tag":…,"props":{…},"each":[{…}],"rev":…}`
    /// — copy a subtree, once or once per row.
    ///
    /// Copying a **reusable** node makes a `ref` to it rather than duplicating
    /// it, which is what Pen does when you place a component. Any other node is
    /// deep-copied with fresh ids. `props` are applied to the copy, never to
    /// the source. `rev` guards `parent`, or the whole document when there is none.
    ///
    /// A key with no slash lands on the copy's root; one written as a name path
    /// (`"Header/Title/kind.content"`) lands on that node *inside* the copy, resolved
    /// against the copy by id — see ``CopyAssignment``, which both this and the `cp`
    /// verb split their keys through.
    ///
    /// ``each`` makes one copy per row instead of one copy: each row is the same kind of
    /// property map ``props`` is, laid over it, with ``CopyAssignment/rowPlaceholder``
    /// substituted for the 1-based row number. It is the batch form of `cp --each`.
    struct CopyOp: Friendly {
        /// Creates a copy operation.
        ///
        /// - Parameters:
        ///   - source: The node to copy or instantiate.
        ///   - parent: The container to insert into, or `nil` for the document root.
        ///   - at: The position among the parent's children, or `nil` to append.
        ///   - tag: A batch tag later lines can address as `@tag`.
        ///   - props: Properties to set on the copy, keyed by ``NodePropertyCodec`` path
        ///     or by a name path into the copy.
        ///   - each: One property map per copy, or `nil` for a single copy.
        ///   - rev: The revision of `parent` — or of the document — the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            source: NodeAddress,
            parent: NodeAddress? = nil,
            at: Int? = nil,
            tag: String? = nil,
            props: [String: AnyCodable]? = nil,
            each: [[String: AnyCodable]]? = nil,
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.source = source
            self.parent = parent
            self.at = at
            self.tag = tag
            self.props = props
            self.each = each
            self.rev = rev
            self.guards = guards
        }

        /// The node to copy or instantiate.
        public var source: NodeAddress
        /// The container to insert into, or `nil` for the document root.
        public var parent: NodeAddress?
        /// The position among the parent's children, or `nil` to append.
        public var at: Int?
        /// A batch tag later lines can address as `@tag`.
        ///
        /// Refused alongside ``each``: a tag names one node, and `each` makes several.
        public var tag: String?
        /// Properties to set on the copy, keyed by ``NodePropertyCodec`` path or by a
        /// name path into the copy.
        ///
        /// With ``each``, these are the defaults every row starts from; a row's own key
        /// wins over them.
        public var props: [String: AnyCodable]?
        /// One property map per copy, or `nil` for a single copy.
        ///
        /// Each row is laid over ``props``, and ``CopyAssignment/rowPlaceholder`` in any
        /// of its values becomes the 1-based row number. An empty array is refused
        /// rather than treated as "copy nothing".
        public var each: [[String: AnyCodable]]?
        /// The revision of `parent` — or of the document — the caller last observed.
        ///
        /// With ``each`` it guards the first copy only: the parent has already changed
        /// by the second, so re-checking the same token would fail against the write
        /// this same line just made.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"mv","target":…,"parent":…,"at":N,"rev":…}` — relocate a node.
    ///
    /// Omitting `parent` moves the node to the document root. `rev` guards `target`.
    struct MoveOp: Friendly {
        /// Creates a move operation.
        ///
        /// - Parameters:
        ///   - target: The node to move.
        ///   - parent: The new container, or `nil` for the document root.
        ///   - at: The position among the new parent's children, or `nil` to append.
        ///   - rev: The revision of `target` the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            target: NodeAddress,
            parent: NodeAddress? = nil,
            at: Int? = nil,
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.target = target
            self.parent = parent
            self.at = at
            self.rev = rev
            self.guards = guards
        }

        /// The node to move.
        public var target: NodeAddress
        /// The new container, or `nil` for the document root.
        public var parent: NodeAddress?
        /// The position among the new parent's children, or `nil` to append.
        public var at: Int?
        /// The revision of `target` the caller last observed.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"rm","target":…,"detach":true,"rev":…}` — delete a node and its descendants.
    ///
    /// Deleting a reusable component is refused while instances of it exist,
    /// because they would silently become plain frames. `detach: true` detaches
    /// every instance first, which is the consequence the caller is opting into.
    /// `rev` guards `target`.
    struct RemoveOp: Friendly {
        /// Creates a remove operation.
        ///
        /// - Parameters:
        ///   - target: The node to delete.
        ///   - detach: Whether to detach every instance of `target` first.
        ///   - rev: The revision of `target` the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            target: NodeAddress,
            detach: Bool = false,
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.target = target
            self.detach = detach
            self.rev = rev
            self.guards = guards
        }

        /// The node to delete.
        public var target: NodeAddress
        /// Whether to detach every instance of `target` before deleting it.
        public var detach: Bool
        /// The revision of `target` the caller last observed.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"override","target":"Instance/Descendant","props":{…},"rev":…}` — override inside an instance.
    ///
    /// `target` must be an address that steps *through* a `ref` node, so it
    /// names a node inside a component instance. Unlike ``SetOp``, the keys in
    /// `props` are raw .pen property names (`"content"`, not `"kind.content"`),
    /// because that is what the format writes into a ref's `descendants` map. `rev`
    /// guards the instance.
    struct OverrideOp: Friendly {
        /// Creates an override operation.
        ///
        /// - Parameters:
        ///   - target: An address naming a node inside a component instance, or the
        ///     instance itself for the component root's own properties.
        ///   - props: Properties to merge, keyed by raw .pen property name.
        ///   - unset: Keys to remove, applied after the merge. Removing an override is
        ///     not the same as overriding with null: a null is stored and clears the
        ///     definition's value, while a removed key lets it show through again.
        ///   - rev: The revision of the instance the caller last observed.
        ///   - guards: Premises to assert at transaction entry. See ``BatchGuard``.
        public init(
            target: NodeAddress,
            props: [String: AnyCodable] = [:],
            unset: [String] = [],
            rev: String? = nil,
            guards: [BatchGuard] = []
        ) {
            self.target = target
            self.props = props
            self.unset = unset
            self.rev = rev
            self.guards = guards
        }

        /// An address naming a node inside a component instance, or the instance itself.
        public var target: NodeAddress
        /// Properties to merge, keyed by raw .pen property name.
        public var props: [String: AnyCodable]
        /// Keys to remove from the override, applied after ``props`` merges.
        public var unset: [String] = []
        /// The revision of the instance the caller last observed.
        public var rev: String?
        /// Premises asserted at transaction entry, before any line of the batch runs.
        public var guards: [BatchGuard]
    }

    /// `{"op":"var","name":…,"value":{…}}` — add or update a document variable.
    ///
    /// The batch grammar does not remove variables: an optional payload would
    /// turn a dropped field into a silent delete.
    struct VariableOp: Friendly {
        /// Creates a variable operation.
        ///
        /// - Parameters:
        ///   - name: The variable's name, without `$`.
        ///   - value: The variable definition.
        ///   - guards: Premises to assert at transaction entry. A variable line acts on
        ///     no node, so each one has to name what it pins. See ``BatchGuard``.
        public init(name: String, value: PenVariable, guards: [BatchGuard] = []) {
            self.name = name
            self.value = value
            self.guards = guards
        }

        /// The variable's name, without `$`.
        public var name: String
        /// The variable definition.
        public var value: PenVariable
        /// Premises asserted at transaction entry, each naming what it pins.
        public var guards: [BatchGuard]
    }

    /// `{"op":"theme-axis","name":…,"options":[…]}` — add or update a theme axis.
    ///
    /// Updating replaces the axis's options wholesale. The batch grammar does
    /// not remove axes, for the same reason it does not remove variables.
    struct ThemeAxisOp: Friendly {
        /// Creates a theme-axis operation.
        ///
        /// - Parameters:
        ///   - name: The axis name (`"mode"`).
        ///   - options: The axis options (`["light", "dark"]`).
        ///   - guards: Premises to assert at transaction entry. A theme-axis line acts
        ///     on no node, so each one has to name what it pins. See ``BatchGuard``.
        public init(name: String, options: [String], guards: [BatchGuard] = []) {
            self.name = name
            self.options = options
            self.guards = guards
        }

        /// The axis name (`"mode"`).
        public var name: String
        /// The axis options (`["light", "dark"]`).
        public var options: [String]
        /// Premises asserted at transaction entry, each naming what it pins.
        public var guards: [BatchGuard]
    }

    /// `{"op":"import","alias":…,"path":…}` — add a library import, or repoint one.
    ///
    /// An alias the document already has has its path changed; one it does not have is
    /// added, exactly as `var` adds or changes. The batch grammar does not *remove* an
    /// import, for the reason it removes no variable: an optional payload would turn a
    /// dropped field into a silent delete, and dropping an alias a `ref` still reaches
    /// into breaks that ref silently. `woodcase imports rm` and `doc.imports.rm` are
    /// where a removal lives, behind the refusal ``NameInUse`` renders.
    struct ImportOp: Friendly {
        /// Creates an import operation.
        ///
        /// - Parameters:
        ///   - alias: The namespace prefix the library's identifiers take (`"V"`).
        ///   - path: The file path or URL the alias resolves to.
        ///   - guards: Premises to assert at transaction entry. An import line acts on no
        ///     node, so each one has to name what it pins. See ``BatchGuard``.
        public init(alias: String, path: String, guards: [BatchGuard] = []) {
            self.alias = alias
            self.path = path
            self.guards = guards
        }

        /// The namespace prefix the library's identifiers take (`"V"`).
        public var alias: String
        /// The file path or URL the alias resolves to.
        public var path: String
        /// Premises asserted at transaction entry, each naming what it pins.
        public var guards: [BatchGuard]
    }
}
