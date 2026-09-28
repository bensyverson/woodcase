//
//  ThemeAxisRegistrar.swift
//  Woodcase
//

import Foundation

/// The one rule for growing a theme: an axis the document lacks is created, an option
/// an axis lacks is appended.
///
/// A themed variable value pins itself to `axis=option` pairs, and a pair naming an axis
/// or an option the `themes` table does not hold leaves the document in a state Pen
/// itself never writes — a value conditioned on a theme nothing can select. Both the
/// `vars set --theme` verb and the batch `var` line therefore register before they
/// write, and they do it here so they cannot come to disagree about it.
///
/// ```swift
/// for registration in ThemeAxisRegistrar.registrations(for: ["mode": ["dark"]], in: document) {
///     try recorder.apply(registration.edit)
/// }
/// ```
///
/// Options are **appended, never reordered**: the first option of an axis is the one
/// that is active when nothing pins it, so inserting would change what renders.
public enum ThemeAxisRegistrar {
    /// One axis a registration creates or widens.
    public struct Registration: Friendly {
        /// Creates a registration.
        ///
        /// - Parameters:
        ///   - name: The axis name.
        ///   - options: The axis's options after the edit, in file order.
        ///   - edit: The edit that creates or widens the axis.
        public init(name: String, options: [String], edit: EditOperation) {
            self.name = name
            self.options = options
            self.edit = edit
        }

        /// The axis name.
        public var name: String

        /// The axis's options after the edit, in file order.
        public var options: [String]

        /// The edit that creates or widens the axis.
        public var edit: EditOperation
    }

    /// What a document needs so that every pin has an axis and an option to name.
    ///
    /// - Parameters:
    ///   - pins: Options wanted, keyed by axis, each list in the order it should be
    ///     appended.
    ///   - document: The document as it stands.
    /// - Returns: One registration per axis this creates or widens, in axis order. An
    ///   axis that already holds every option asked for is absent — there is nothing to
    ///   do and nothing to report.
    public static func registrations(
        for pins: [String: [String]],
        in document: EditableDocument
    ) -> [Registration] {
        pins.sorted { $0.key < $1.key }.compactMap { axis, wanted in
            guard let existing = document.themes?[axis] else {
                let options = ordered(wanted)
                return Registration(
                    name: axis,
                    options: options,
                    edit: .addThemeAxis(EditOperation.AddThemeAxis(name: axis, options: options))
                )
            }
            let missing = ordered(wanted).filter { !existing.contains($0) }
            guard !missing.isEmpty else { return nil }
            let widened = existing + missing
            return Registration(
                name: axis,
                options: widened,
                edit: .updateThemeAxis(EditOperation.UpdateThemeAxis(name: axis, options: widened))
            )
        }
    }

    // MARK: - Private

    /// The options, each once, in the order they were first asked for.
    private static func ordered(_ options: [String]) -> [String] {
        var seen: Set<String> = []
        return options.filter { seen.insert($0).inserted }
    }
}
