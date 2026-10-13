//
//  EditRefusal+NestedLocation.swift
//  Woodcase
//

import Foundation

public extension EditRefusal {
    /// Where inside a structured property's value a refusal found the offending value:
    /// the path of keys and array indices from the property's value down to it.
    ///
    /// For a gradient stop at position 2 in the second paint of `kind.fills`, the
    /// components are `[.index(1), .key("colors"), .index(1), .key("position")]`:
    /// ``layerIndex`` is 1, ``key`` is `"position"`. A paint written as one object, not
    /// an array, has no leading index, so ``layerIndex`` is `nil`. The refusal's
    /// ``EditRefusal/property`` stays the key that was written (`kind.fills`).
    ///
    /// ```swift
    /// refusal.nested?.layerIndex   // 1
    /// refusal.nested?.key          // "position"
    /// ```
    struct NestedLocation: Friendly {
        /// One step down into a value.
        public enum Component: Friendly {
            /// An object's key.
            case key(String)

            /// An array's element.
            case index(Int)
        }

        /// Creates a location.
        ///
        /// - Parameter components: The steps from the property's value down to the value.
        public init(components: [Component]) {
            self.components = components
        }

        /// The steps from the property's value down to the value, outermost first.
        public var components: [Component]

        /// Every array index on the way, outermost first.
        public var indices: [Int] {
            components.compactMap { if case let .index(index) = $0 { index } else { nil } }
        }

        /// Every object key on the way, outermost first.
        public var keys: [String] {
            components.compactMap { if case let .key(key) = $0 { key } else { nil } }
        }

        /// The index of the element of the property's own array the value sits in — the
        /// paint or effect layer — or `nil` when the property's value is one object.
        public var layerIndex: Int? {
            if case let .index(index)? = components.first { index } else { nil }
        }

        /// The key that holds the value: the last key on the way.
        public var key: String? {
            keys.last
        }

        /// The location as the refusal's sentence writes it, under the property's key:
        /// `kind.fills[1].colors[1].position`.
        ///
        /// - Parameter property: The key the write named.
        /// - Returns: The key with each step appended.
        public func spelled(under property: String) -> String {
            components.reduce(property) { spelled, component in
                switch component {
                case let .key(key): "\(spelled).\(key)"
                case let .index(index): "\(spelled)[\(index)]"
                }
            }
        }
    }
}
