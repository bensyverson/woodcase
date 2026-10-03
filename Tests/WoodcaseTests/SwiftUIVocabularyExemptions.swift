//
//  SwiftUIVocabularyExemptions.swift
//  WoodcaseTests
//

/// Names the emitted code uses that are not SDK APIs, so are not on
/// `swiftui-vocabulary.txt` and never audited.
///
/// Keep it short: an entry here is a name the churn guard stops watching. The Swift
/// standard library is the language, not the SDK; the rest is what the symbol graph does not
/// record. Anything an Apple framework declares belongs on the vocabulary list instead.
enum SwiftUIVocabularyExemptions {
    /// The exempt names, in the vocabulary's path syntax: a use is exempt when one of these
    /// covers it the way a listed path would.
    static let list = SwiftUIVocabulary(paths: standardLibrary + concurrency + unrecorded)

    /// The Swift standard library and its `Synchronization` module.
    private static let standardLibrary = [
        "Any", "Array.init(_:)", "Bool", "CaseIterable", "CaseIterable.allCases", "Character.init(_:)",
        "Double", "Double.init(_:)", "Equatable", "ExpressibleByArrayLiteral", "Float", "Float.init(_:)",
        "Hashable", "Int", "Int.init(_:)", "KeyPath", "OptionSet", "Sendable", "SIMD2", "SIMD2.init(_:_:)",
        "String", "String.init(_:)", "UInt32", "Unicode.Scalar.init(_:)", "Void", "CommandLine.arguments",
        "abs(_:)", "max(_:_:)", "min(_:_:)", "zip(_:_:)", "print(_:)", "precondition(_:_:)",
        "Array.append(_:)", "Array.reserveCapacity(_:)", "Bool.toggle()", "Collection.indices",
        "Collection.first", "Collection.firstIndex(of:)", "Optional.flatMap(_:)", "Optional.map(_:)",
        "Sequence.map(_:)", "Sequence.reduce(_:_:)", "SetAlgebra.contains(_:)", "SetAlgebra.insert(_:)",
        "String.utf8", "String.utf16", "FloatingPoint.rounded()", "FloatingPoint.rounded(_:)", "FloatingPointRoundingRule.up", "FloatingPoint.pi", "FloatingPoint.infinity",
        "RawRepresentable.rawValue", "Mutex", "Mutex.withLock(_:)", "Sequence.allSatisfy(_:)",
        "Sequence.compactMap(_:)", "Sequence.first(where:)", "Sequence.sorted(by:)", "Unmanaged",
        "Unmanaged.takeRetainedValue()", "Sequence.filter(_:)", "Collection.isEmpty", "Collection.startIndex",
        "Sequence.min()", "Sequence.min(by:)", "UInt32.init(_:)", "FloatingPoint.squareRoot()",
    ]

    /// Swift concurrency's global actor, which emitted code names only in `main.swift`.
    private static let concurrency = ["MainActor"]

    /// What the symbol graph does not record: Core Graphics' C structs (their fields and
    /// memberwise initializers are imported, not declared), Core Foundation's bridged types,
    /// Core Foundation's error accessor, the C library's `exit`, `cos` and `sin`, and
    /// SwiftPM's generated `Bundle.module`.
    private static let unrecorded = [
        "CGFloat", "CGFloat.init(_:)", "CGPoint", "CGSize", "CGRect", "CGRect.init(origin:size:)",
        "CGAffineTransform.a", "CGAffineTransform.b", "CGAffineTransform.c", "CGAffineTransform.d",
        "CGAffineTransform.init(a:b:c:d:tx:ty:)",
        "CFString", "CFDictionary", "CFURL", "CFError", "CFErrorGetCode(_:)", "exit(_:)", "cos(_:)", "sin(_:)",
        "Bundle.module",
    ]
}
