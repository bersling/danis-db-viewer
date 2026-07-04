import Foundation

/// A single cell value, normalized across drivers.
enum DBValue: Hashable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case bool(Bool)
    case blob(Data)

    var isNull: Bool { if case .null = self { return true }; return false }

    /// What the grid displays.
    var displayString: String {
        switch self {
        case .null: return "<null>"
        case .int(let v): return String(v)
        case .double(let v):
            if v == v.rounded() && abs(v) < 1e15 {
                return String(format: "%.1f", v)
            }
            return String(v)
        case .text(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .blob(let d): return "0x" + d.prefix(64).map { String(format: "%02X", $0) }.joined() + (d.count > 64 ? "… (\(d.count) bytes)" : "")
        }
    }

    /// Editable text representation (round-trips through `parse`).
    var editString: String {
        switch self {
        case .null: return ""
        case .blob(let d): return d.map { String(format: "%02X", $0) }.joined()
        default: return displayString
        }
    }

    /// Parse user-entered text back into a value, guided by the column's declared type.
    static func parse(_ text: String, forDeclaredType type: String) -> DBValue {
        let t = type.lowercased()
        if t.contains("int") || t.contains("serial") {
            if let i = Int64(text) { return .int(i) }
        }
        if t.contains("real") || t.contains("floa") || t.contains("doub") || t.contains("numeric") || t.contains("decimal") {
            if let d = Double(text) { return .double(d) }
        }
        if t.contains("bool") {
            let lower = text.lowercased()
            if ["true", "t", "1", "yes"].contains(lower) { return .bool(true) }
            if ["false", "f", "0", "no"].contains(lower) { return .bool(false) }
        }
        return .text(text)
    }

    /// SQL literal for INSERT export / generated statements (driver-agnostic fallback).
    var sqlLiteral: String {
        switch self {
        case .null: return "NULL"
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .text(let s): return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
        case .blob(let d): return "X'" + d.map { String(format: "%02X", $0) }.joined() + "'"
        }
    }

    /// JSON-compatible representation for export.
    var jsonValue: Any {
        switch self {
        case .null: return NSNull()
        case .int(let v): return v
        case .double(let v): return v
        case .text(let s): return s
        case .bool(let b): return b
        case .blob(let d): return d.base64EncodedString()
        }
    }
}
