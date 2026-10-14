//
//  PasteVariables.swift
//  Woodcase
//

import Foundation

/// How a paste brings a clip's variables into a target: which it reuses, which it renames,
/// and which it adds.
///
/// A clip variable the target has under the same name **with the same definition** is
/// reused. "The same definition" is equality of ``PenVariable`` — type and value, every
/// themed variant with its pins — after the clip's own `$name` references are read in the
/// target's terms: a reference to a variable that is itself reused or added under its own
/// name reads as written, and one to a variable that has to be renamed reads as something
/// the target cannot hold, so `$accent: $brand` is reused only when `brand` is too. That
/// is a greatest fixpoint: every same-name pair starts out equal, and a pair is dropped
/// when its values differ under the current reading, until nothing more drops.
///
/// A variable the target lacks is added as it is; one whose name the target holds with a
/// different definition is added renamed (`primary` → `primary-2`, ``PasteNames``), and
/// every `$name` in the paste follows. The target's variables are its own and its imported
/// libraries', so a library variable both documents read (`$K:accent`) is reused too.
struct PasteVariables: Friendly {
    /// Clip name → the name the variable has in the target, for every clip variable.
    var names: [String: String]

    /// The clip's variables the target already has, sorted.
    var reused: [String]

    /// The variables renamed, sorted by the clip's name.
    var renamed: [PastePlan.Rename]

    /// The operations that add the variables the target lacks, sorted by their new name.
    var operations: [EditOperation]

    /// Works out the variables of a paste.
    ///
    /// - Parameters:
    ///   - clip: The clip's variables, by name.
    ///   - target: The target's variables, own and imported, by name.
    init(clip: [String: PenVariable], target: [String: PenVariable]) {
        var equal = Set(clip.keys.filter { target[$0] != nil })
        var changed = true
        while changed {
            changed = false
            for name in equal.sorted() {
                guard let mine = clip[name] else { continue }
                let read = Self.renaming(mine) { reference in
                    equal.contains(reference) || target[reference] == nil ? reference : Self.unreadable
                }
                if read != target[name] {
                    equal.remove(name)
                    changed = true
                }
            }
        }

        var taken = Set(target.keys).union(clip.keys)
        var names: [String: String] = [:]
        var renamed: [PastePlan.Rename] = []
        for name in clip.keys.sorted() {
            guard target[name] != nil, !equal.contains(name) else {
                names[name] = name
                continue
            }
            let fresh = PasteNames.variable(name, avoiding: taken)
            taken.insert(fresh)
            names[name] = fresh
            renamed.append(PastePlan.Rename(from: name, to: fresh))
        }

        self.names = names
        reused = equal.sorted()
        self.renamed = renamed
        operations = clip.keys
            .filter { !equal.contains($0) }
            .compactMap { name -> (String, PenVariable)? in
                guard let variable = clip[name] else { return nil }
                return (names[name] ?? name, Self.renaming(variable) { names[$0] ?? $0 })
            }
            .sorted { $0.0 < $1.0 }
            .map { .addVariable(EditOperation.AddVariable(name: $0.0, variable: $0.1)) }
    }

    /// The names that changed: clip name → new name, for the renamed ones only.
    var changes: [String: String] {
        Dictionary(uniqueKeysWithValues: renamed.map { ($0.from, $0.to) })
    }

    /// A variable with every `$name` in its values passed through `rename`.
    ///
    /// - Parameters:
    ///   - variable: The variable.
    ///   - rename: Name → the name to write.
    /// - Returns: The variable, its references renamed.
    static func renaming(_ variable: PenVariable, _ rename: (String) -> String) -> PenVariable {
        var result = variable
        switch variable.value {
        case let .simple(value):
            result.value = .simple(PasteRewriter.renamingVariables(in: value, rename))
        case let .themed(variants):
            result.value = .themed(variants.map { variant in
                var renamed = variant
                renamed.value = PasteRewriter.renamingVariables(in: variant.value, rename)
                return renamed
            })
        }
        return result
    }

    /// A name no variable can have, read in place of a reference to a variable that is
    /// being renamed, so a definition that uses it never equals the target's.
    private static let unreadable = "\u{0}renamed"
}
