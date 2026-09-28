//
//  AddressArgument.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Turns the `<node>` and `<parent|document>` words on a command line into a
/// ``NodeAddress``.
///
/// Parsing an address can only fail *syntactically* — an empty segment, a bare `@`.
/// Whether it names anything is a question for the document, and the document
/// answers it with a message listing near misses. So this stage's whole job is to
/// refuse the handful of shapes that are not addresses at all, and to teach the
/// three that are.
///
/// The one word that is not an address is `document`, which stands for the document
/// root wherever a parent is expected. A root node genuinely named `document` is
/// still addressable — as `#<id>`, or through a longer path — which is the trade a
/// literal always asks for.
enum AddressArgument {
    /// The word that means the document root where a parent is expected.
    ///
    /// The library's own constant, so argv, a batch line and a guard cannot drift apart
    /// on the one word that is not an address.
    static let documentRoot = NodeAddress.documentRoot

    /// The forms an address can take, as a verb's help prints them.
    static let addressForms = """
    An address is an id (ALu8G), a path of names from any ancestor \
    (Dashboard/Header/Title), a path into a component instance (Orders/Value), or \
    an id forced with # (#ALu8G). `woodcase tree <file>` lists them.
    """

    /// Parses the address of a node the verb acts on.
    ///
    /// - Parameter raw: The address as typed.
    /// - Returns: The parsed address.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when the string is not an
    ///   address at all.
    static func node(_ raw: String) throws -> NodeAddress {
        guard let address = NodeAddress(raw) else {
            throw CommandFailure(
                message: "\(raw.isEmpty ? "an empty string" : raw) is not an address. "
                    + addressForms,
                exitCode: .usage
            )
        }
        return address
    }

    /// Parses the address of a parent, where `document` means the document root.
    ///
    /// - Parameter raw: The address as typed, or `document`.
    /// - Returns: The parsed address, or `nil` for the document root.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when the string is not an
    ///   address at all.
    static func parent(_ raw: String) throws -> NodeAddress? {
        guard raw != documentRoot else { return nil }
        guard let address = NodeAddress(raw) else {
            throw CommandFailure(
                message: "\(raw.isEmpty ? "an empty string" : raw) is not a parent. "
                    + "Name a frame or a group, or `document` for the document root. "
                    + addressForms,
                exitCode: .usage
            )
        }
        return address
    }
}
