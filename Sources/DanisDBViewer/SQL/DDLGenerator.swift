import Foundation

/// Assembles CREATE TABLE DDL from introspected structure (used where the DBMS
/// has no SHOW CREATE TABLE equivalent).
enum DDLGenerator {
    static func createTable(_ table: DBTableInfo, quote: (String) -> String) -> String {
        var lines: [String] = []
        for col in table.columns {
            var line = "    \(quote(col.name)) \(col.typeName)"
            if !col.isNullable { line += " NOT NULL" }
            if let def = col.defaultValue, !def.isEmpty { line += " DEFAULT \(def)" }
            lines.append(line)
        }
        let pk = table.primaryKeyColumns
        if !pk.isEmpty {
            lines.append("    PRIMARY KEY (\(pk.map(quote).joined(separator: ", ")))")
        }
        for fk in table.foreignKeys {
            let cols = fk.columns.map(quote).joined(separator: ", ")
            let refCols = fk.referencedColumns.map(quote).joined(separator: ", ")
            let refTable = fk.referencedSchema.isEmpty
                ? quote(fk.referencedTable)
                : "\(quote(fk.referencedSchema)).\(quote(fk.referencedTable))"
            lines.append("    CONSTRAINT \(quote(fk.name)) FOREIGN KEY (\(cols)) REFERENCES \(refTable) (\(refCols))")
        }
        let target = table.schema.isEmpty
            ? quote(table.name)
            : "\(quote(table.schema)).\(quote(table.name))"
        var ddl = "CREATE \(table.kind == .view ? "VIEW" : "TABLE") \(target)\n(\n"
        ddl += lines.joined(separator: ",\n")
        ddl += "\n);"
        for idx in table.indexes {
            let cols = idx.columns.map(quote).joined(separator: ", ")
            ddl += "\n\nCREATE \(idx.isUnique ? "UNIQUE " : "")INDEX \(quote(idx.name)) ON \(target) (\(cols));"
        }
        return ddl
    }
}
