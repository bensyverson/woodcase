import Foundation

/// Splits SVG path data into command letters and numbers.
///
/// Lenient by design, as Pen is: whitespace and commas separate, a sign or a second
/// decimal point starts a new number, and any other character is skipped.
enum PenSVGPathTokenizer {
    /// One lexical token of path data.
    enum Token: Friendly {
        /// A command letter. Any letter is tokenized; the reader rejects the ones SVG does not define.
        case command(String)
        /// A number, with the text it was read from: an arc flag may be the first digit of a
        /// longer run (`01` is two flags), which only the text can tell.
        case number(Double, text: String)
    }

    /// Tokenizes path data.
    static func tokenize(_ pathData: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(pathData)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "," {
                i += 1
                continue
            }

            if ch.isLetter {
                tokens.append(.command(String(ch)))
                i += 1
                continue
            }

            if ch == "-" || ch == "+" || ch == "." || ch.isNumber {
                var text = String(ch)
                i += 1
                var hasDecimal = ch == "."
                while i < chars.count {
                    let next = chars[i]
                    if next.isNumber {
                        text.append(next)
                        i += 1
                    } else if next == ".", !hasDecimal {
                        hasDecimal = true
                        text.append(next)
                        i += 1
                    } else if next == "e" || next == "E" {
                        text.append(next)
                        i += 1
                        if i < chars.count, chars[i] == "+" || chars[i] == "-" {
                            text.append(chars[i])
                            i += 1
                        }
                    } else {
                        break
                    }
                }
                // A lone sign or point reads as no number at all.
                if let value = Double(text) {
                    tokens.append(.number(value, text: text))
                }
                continue
            }

            i += 1
        }

        return tokens
    }
}
