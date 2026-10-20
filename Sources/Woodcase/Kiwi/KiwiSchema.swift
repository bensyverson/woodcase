//
//  KiwiSchema.swift
//  Woodcase
//

/// A compiled Kiwi schema: its definitions, checked so that any message can be decoded
/// against them without trusting the schema itself.
///
/// Build one from the binary schema a payload carries with ``init(binary:)``, or from
/// definitions with ``init(definitions:)``, then decode messages with
/// ``decode(_:as:maxDepth:)``. Nothing about any particular application's schema is built
/// in: every name the decoder uses comes from the definitions.
public struct KiwiSchema: Sendable {
    /// The deepest nesting of structs and messages ``decode(_:as:maxDepth:)`` follows by
    /// default, counting the root as one.
    public static let defaultMaxDepth = 64

    /// The definitions, in schema order.
    public let definitions: [KiwiDefinition]

    /// Each definition's index, by name.
    let indexByName: [String: Int]
    /// For each definition, its fields' indices by field value.
    let fieldIndexByValue: [[UInt32: Int]]

    /// Compiles `definitions`, checking names, field values, field types and struct
    /// recursion.
    ///
    /// - Throws: ``KiwiDecodingError`` naming the first definition that cannot be decoded
    ///   against.
    public init(definitions: [KiwiDefinition]) throws(KiwiDecodingError) {
        var indexByName: [String: Int] = [:]
        for (index, definition) in definitions.enumerated() {
            guard indexByName.updateValue(index, forKey: definition.name) == nil else {
                throw .duplicateDefinition(definition.name)
            }
        }
        var fieldIndexByValue: [[UInt32: Int]] = []
        fieldIndexByValue.reserveCapacity(definitions.count)
        for definition in definitions {
            try fieldIndexByValue.append(Self.compileFields(of: definition, names: indexByName))
        }
        try Self.checkStructRecursion(definitions, indexByName: indexByName)
        self.definitions = definitions
        self.indexByName = indexByName
        self.fieldIndexByValue = fieldIndexByValue
    }

    /// The definition with the given name.
    public func definition(named name: String) -> KiwiDefinition? {
        indexByName[name].map { definitions[$0] }
    }

    /// Checks one definition's fields and indexes them by value.
    private static func compileFields(
        of definition: KiwiDefinition,
        names: [String: Int]
    ) throws(KiwiDecodingError) -> [UInt32: Int] {
        var seenNames: Set<String> = []
        var byValue: [UInt32: Int] = [:]
        for (index, field) in definition.fields.enumerated() {
            guard seenNames.insert(field.name).inserted else {
                throw .duplicateFieldName(definition: definition.name, field: field.name)
            }
            guard byValue.updateValue(index, forKey: field.value) == nil else {
                throw .duplicateFieldValue(definition: definition.name, value: field.value)
            }
            guard definition.kind != .enumeration else { continue }
            switch field.type {
            case .none:
                throw .missingFieldType(definition: definition.name, field: field.name)
            case let .definition(name) where names[name] == nil:
                throw .undefinedFieldType(definition: definition.name, field: field.name, type: name)
            default:
                break
            }
        }
        return byValue
    }

    /// Refuses a struct that contains itself through non-array struct fields, which no
    /// finite input can encode.
    ///
    /// Peels off structs whose struct fields are all resolved until none are left; any
    /// that remain lie on or lead into a cycle. Iterative, so a hostile chain of
    /// definitions cannot exhaust the stack.
    private static func checkStructRecursion(
        _ definitions: [KiwiDefinition],
        indexByName: [String: Int]
    ) throws(KiwiDecodingError) {
        var dependencies: [Int: [Int]] = [:]
        var dependents: [Int: [Int]] = [:]
        for (index, definition) in definitions.enumerated() where definition.kind == .structure {
            var needs: [Int] = []
            for field in definition.fields where !field.isArray {
                guard case let .definition(name) = field.type, let target = indexByName[name],
                      definitions[target].kind == .structure else { continue }
                needs.append(target)
                dependents[target, default: []].append(index)
            }
            dependencies[index] = needs
        }
        var unresolved = dependencies.mapValues(\.count)
        var ready = unresolved.filter { $0.value == 0 }.map(\.key)
        while let next = ready.popLast() {
            unresolved[next] = nil
            for dependent in dependents[next] ?? [] {
                unresolved[dependent]? -= 1
                if unresolved[dependent] == 0 { ready.append(dependent) }
            }
        }
        guard var current = unresolved.keys.min() else { return }
        // Every unresolved struct has an unresolved dependency; following them for as many
        // steps as there are unresolved structs must end inside a cycle.
        for _ in 0 ..< unresolved.count {
            guard let step = dependencies[current]?.first(where: { unresolved[$0] != nil }) else { break }
            current = step
        }
        throw .recursiveStruct(definitions[current].name)
    }
}
