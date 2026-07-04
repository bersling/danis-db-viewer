import Foundation

/// Splits a SQL script into individual statements, respecting string literals,
/// quoted identifiers, and line/block comments.
enum SQLSplitter {
    static func split(_ script: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var chars = Array(script)
        var i = 0

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { statements.append(trimmed) }
            current = ""
        }

        while i < chars.count {
            let c = chars[i]

            // Line comment
            if c == "-" && i + 1 < chars.count && chars[i + 1] == "-" {
                while i < chars.count && chars[i] != "\n" { current.append(chars[i]); i += 1 }
                continue
            }
            // Block comment
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                current.append(chars[i]); current.append(chars[i + 1]); i += 2
                while i < chars.count {
                    if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                        current.append(chars[i]); current.append(chars[i + 1]); i += 2
                        break
                    }
                    current.append(chars[i]); i += 1
                }
                continue
            }
            // Quoted regions: '...', "...", `...`
            if c == "'" || c == "\"" || c == "`" {
                let quote = c
                current.append(c); i += 1
                while i < chars.count {
                    current.append(chars[i])
                    if chars[i] == quote {
                        // doubled quote = escaped
                        if i + 1 < chars.count && chars[i + 1] == quote {
                            i += 1
                            current.append(chars[i])
                        } else {
                            i += 1
                            break
                        }
                    }
                    i += 1
                }
                continue
            }
            // Postgres dollar-quoted strings: $tag$ ... $tag$
            if c == "$" {
                if let (tag, tagLen) = dollarTag(chars, at: i) {
                    for k in 0..<tagLen { current.append(chars[i + k]) }
                    i += tagLen
                    while i < chars.count {
                        if chars[i] == "$", let (endTag, endLen) = dollarTag(chars, at: i), endTag == tag {
                            for k in 0..<endLen { current.append(chars[i + k]) }
                            i += endLen
                            break
                        }
                        current.append(chars[i]); i += 1
                    }
                    continue
                }
            }
            if c == ";" {
                flush()
                i += 1
                continue
            }
            current.append(c)
            i += 1
        }
        flush()
        return statements
    }

    private static func dollarTag(_ chars: [Character], at start: Int) -> (tag: String, length: Int)? {
        guard chars[start] == "$" else { return nil }
        var j = start + 1
        var tag = ""
        while j < chars.count {
            let ch = chars[j]
            if ch == "$" { return (tag, j - start + 1) }
            if !(ch.isLetter || ch.isNumber || ch == "_") { return nil }
            tag.append(ch)
            j += 1
        }
        return nil
    }

    /// The statement containing the caret offset — IntelliJ's "execute statement
    /// at caret". Returns nil for an empty script.
    static func statement(at offset: Int, in script: String) -> String? {
        let parts = split(script)
        guard !parts.isEmpty else { return nil }
        // Walk the script re-locating each statement to find offset ownership.
        var searchStart = script.startIndex
        var lastEnd = 0
        for part in parts {
            guard let range = script.range(of: part, range: searchStart..<script.endIndex) else { continue }
            let start = script.distance(from: script.startIndex, to: range.lowerBound)
            let end = script.distance(from: script.startIndex, to: range.upperBound)
            if offset <= end && offset >= lastEnd { return part }
            searchStart = range.upperBound
            lastEnd = end
        }
        return parts.last
    }
}
