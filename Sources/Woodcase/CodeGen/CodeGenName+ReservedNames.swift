//
//  CodeGenName+ReservedNames.swift
//  Woodcase
//

extension CodeGenName {
    /// The suffix a component whose name is reserved takes: `Text` is `TextComponent`.
    static let reservedComponentSuffix = "Component"

    /// The suffix a page whose name is reserved, or is a component's, takes: `String` is
    /// `StringPage`.
    static let reservedPageSuffix = "Page"

    /// The names a component, a page or an icon import may not take, since the emitted code
    /// would declare a name the module — or a harness page that inlines it — already means
    /// something by: `function String` shadows JavaScript's `String` in its module, and at
    /// the top of a classic script replaces the window's.
    ///
    /// Case-sensitive, as JavaScript is; only names that start upper-case are listed, since
    /// ``typeName(_:droppingPrefixes:)`` capitalizes every name it makes. Four sources:
    /// ``ecmaScriptGlobals``, ``webPlatformGlobals``, ``reactNames`` and ``packageNames``.
    static let reservedNames: Set<String> = ecmaScriptGlobals
        .union(webPlatformGlobals)
        .union(reactNames)
        .union(packageNames)

    /// Every upper-case property of ECMAScript's global object: ECMA-262 (2025, with
    /// ES2026's `DisposableStack`, `AsyncDisposableStack`, `SuppressedError` and the
    /// `Temporal` proposal engines ship) §19.1–19.4 — its value properties, constructors
    /// and namespaces — with ECMA-402's `Intl` and the WebAssembly JS API's namespace.
    static let ecmaScriptGlobals: Set<String> = [
        // §19.1 value properties
        "Infinity", "NaN",
        // §19.3 constructor properties
        "AggregateError", "Array", "ArrayBuffer", "AsyncDisposableStack", "BigInt", "BigInt64Array",
        "BigUint64Array", "Boolean", "DataView", "Date", "DisposableStack", "Error", "EvalError",
        "FinalizationRegistry", "Float16Array", "Float32Array", "Float64Array", "Function", "Int8Array",
        "Int16Array", "Int32Array", "Iterator", "Map", "Number", "Object", "Promise", "Proxy", "RangeError",
        "ReferenceError", "RegExp", "Set", "SharedArrayBuffer", "String", "SuppressedError", "Symbol",
        "SyntaxError", "TypeError", "Uint8Array", "Uint8ClampedArray", "Uint16Array", "Uint32Array",
        "URIError", "WeakMap", "WeakRef", "WeakSet",
        // §19.4 other properties, ECMA-402 and the WebAssembly JS API
        "Atomics", "Intl", "JSON", "Math", "Reflect", "Temporal", "WebAssembly",
    ]

    /// The web platform's constructors and namespaces that a module's own code, or code
    /// beside it, calls by name: the WHATWG DOM (`Node`, `Element`, `Document`, `Text`,
    /// `Comment`, `Event`, …), HTML (`Window`, `Image`, `Audio`, `Option`, `Worker`, …),
    /// Fetch (`Request`, `Response`, `Headers`, `FormData`), URL, File API, Encoding,
    /// Streams and the observers, with CSSOM's `CSS` namespace. Not every interface a
    /// browser's window carries — several hundred, most never called by name — so a
    /// component named `Screen` or `Animation` keeps its name.
    static let webPlatformGlobals: Set<String> = [
        // DOM
        "AbortController", "AbortSignal", "Attr", "CharacterData", "Comment", "CustomEvent", "Document",
        "DocumentFragment", "Element", "Event", "EventTarget", "HTMLCollection", "MutationObserver", "Node",
        "NodeList", "Range", "ShadowRoot", "Text",
        // HTML
        "Audio", "BroadcastChannel", "History", "ImageBitmap", "ImageData", "Image", "Location", "MessageChannel",
        "MessagePort", "Navigator", "OffscreenCanvas", "Option", "Path2D", "Storage", "Window", "Worker",
        // Fetch, URL, File API, Encoding, Streams, XHR, WebSockets
        "Blob", "File", "FileReader", "FormData", "Headers", "ReadableStream", "Request", "Response",
        "TextDecoder", "TextEncoder", "URL", "URLSearchParams", "WebSocket", "WritableStream", "XMLHttpRequest",
        // Observers, and the rest a component's code reaches for
        "CSS", "Crypto", "IntersectionObserver", "Notification", "Performance", "ResizeObserver", "Selection",
    ]

    /// What the `react` and `react-dom` packages export under a capitalized name, which a
    /// module imports beside its components (`import React, { Fragment } from "react"`),
    /// and the globals their UMD builds define.
    static let reactNames: Set<String> = [
        "Activity", "Children", "Component", "Fragment", "Profiler", "PureComponent", "React", "ReactDOM",
        "StrictMode", "Suspense",
    ]

    /// What the generated package itself exports beside the components and pages, which
    /// its barrel re-exports under the same names.
    static let packageNames: Set<String> = ["ThemeProvider"]
}
