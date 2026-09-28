// The render harness `SwiftUIRenderTests` compiles together with every emitted view.
//
// Usage: harness <output directory> [<font directory>...]
//
// Registers every .ttf/.otf under each font directory for this process, then renders each
// board `renderBoards()` lists (a file the test writes beside this one) with ImageRenderer
// at the board's scale, and writes `<output directory>/<name>.png`. The comparison happens
// back in the test process: MAE loops compiled at -Onone here would dominate the run.
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: harness <output directory> [<font directory>...]\n".utf8))
    exit(64)
}

let output = URL(fileURLWithPath: arguments[1], isDirectory: true)

for directory in arguments.dropFirst(2) {
    guard let files = FileManager.default.enumerator(atPath: directory) else { continue }
    for case let file as String in files where file.hasSuffix(".ttf") || file.hasSuffix(".otf") {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(file)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

var failures = 0
MainActor.assumeIsolated {
    for board in renderBoards() {
        // Pinned light: a Material's tint follows the scheme, and the machine's appearance
        // must not move a board's MAE.
        let renderer = ImageRenderer(content: board.view.environment(\.colorScheme, .light))
        renderer.scale = board.scale
        let url = output.appendingPathComponent("\(board.name).png")
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            FileHandle.standardError.write(Data("error: \(board.name) did not render\n".utf8))
            failures += 1
            continue
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            FileHandle.standardError.write(Data("error: \(board.name) PNG was not written\n".utf8))
            failures += 1
        }
    }
}

exit(failures == 0 ? 0 : 1)
