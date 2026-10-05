//
//  ComponentLoopNote.swift
//  WoodcaseCommandCore
//

import Foundation
import Synchronization
import Woodcase

/// The loud line a verb prints when the file it read holds a component loop.
///
/// The library records the loops a read met on ``Woodcase/PenReadContext/componentLoops``
/// and says nothing — an editor shows its own alert from them. The CLI says them here,
/// on standard error, one `woodcase: error:` line per loop, once per file per command:
/// a verb that opens its file twice says it once.
enum ComponentLoopNote {
    /// The files this process has already reported on.
    private static let reported = Mutex<Set<String>>([])

    /// Says the loops a read recorded, unless this file's were said already.
    ///
    /// - Parameter context: The read context the transaction gave the document.
    static func say(_ context: PenReadContext) {
        guard !context.componentLoops.isEmpty else { return }
        let file = context.sourceURL?.path ?? "this document"
        guard reported.withLock({ $0.insert(file).inserted }) else { return }
        for loop in context.componentLoops {
            StandardError.write(line(for: loop, in: file))
        }
    }

    /// The line for one loop.
    ///
    /// - Parameters:
    ///   - loop: The loop.
    ///   - file: The file's path.
    /// - Returns: The message, with the command that lists every loop.
    static func line(for loop: ComponentLoop, in file: String) -> String {
        "woodcase: error: \(file) holds components that contain each other: \(loop). "
            + "That nesting is ignored to avoid an infinite loop; remove the instance that closes it "
            + "(`woodcase lint \(file)` lists every loop)."
    }
}
