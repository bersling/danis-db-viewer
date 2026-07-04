import Foundation

/// Result-set exporters (IntelliJ's "Export Data": CSV, JSON, SQL INSERTs).
enum Exporter {
    static func csv(columns: [String], rows: [[DBValue]]) -> String {
        var out = columns.map(csvEscape).joined(separator: ",") + "\n"
        for row in rows {
            out += row.map { $0.isNull ? "" : csvEscape($0.displayString) }.joined(separator: ",") + "\n"
        }
        return out
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func json(columns: [String], rows: [[DBValue]]) -> String {
        let objects: [[String: Any]] = rows.map { row in
            var obj: [String: Any] = [:]
            for (i, col) in columns.enumerated() where i < row.count {
                obj[col] = row[i].jsonValue
            }
            return obj
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func sqlInserts(table: String, columns: [String], rows: [[DBValue]], quote: (String) -> String) -> String {
        let cols = columns.map(quote).joined(separator: ", ")
        return rows.map { row in
            "INSERT INTO \(quote(table)) (\(cols)) VALUES (\(row.map(\.sqlLiteral).joined(separator: ", ")));"
        }.joined(separator: "\n")
    }
}
