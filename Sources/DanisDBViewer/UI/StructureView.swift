import SwiftUI

/// Structure detail for an open table: columns, indexes, foreign keys.
struct StructureView: View {
    let info: DBTableInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Columns") {
                    structureGrid(
                        header: ["Name", "Type", "Nullable", "Default", "Attributes"],
                        rows: info.columns.map { col in
                            [col.name, col.typeName.lowercased(),
                             col.isNullable ? "yes" : "no",
                             col.defaultValue ?? "",
                             attributes(col)]
                        })
                }
                if !info.indexes.isEmpty {
                    section("Indexes") {
                        structureGrid(
                            header: ["Name", "Columns", "Unique"],
                            rows: info.indexes.map { [$0.name, $0.columns.joined(separator: ", "), $0.isUnique ? "yes" : "no"] })
                    }
                }
                if !info.foreignKeys.isEmpty {
                    section("Foreign Keys") {
                        structureGrid(
                            header: ["Name", "Columns", "References"],
                            rows: info.foreignKeys.map {
                                [$0.name, $0.columns.joined(separator: ", "),
                                 "\($0.referencedTable) (\($0.referencedColumns.joined(separator: ", ")))"]
                            })
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.editorBackground)
    }

    private func attributes(_ col: DBColumnInfo) -> String {
        var attrs: [String] = []
        if col.isPrimaryKey { attrs.append("PK") }
        if col.isAutoIncrement { attrs.append("auto increment") }
        return attrs.joined(separator: ", ")
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dimText)
            content()
        }
    }

    private func structureGrid(header: [String], rows: [[String]]) -> some View {
        let widths = gridWidths(header: header, rows: rows)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(header.indices, id: \.self) { i in
                    Text(header[i])
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .frame(width: widths[i], alignment: .leading)
                        .background(Theme.toolWindowBackground)
                        .border(Theme.gridLine, width: 0.5)
                }
            }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(header.indices, id: \.self) { c in
                        Text(c < rows[r].count ? rows[r][c] : "")
                            .font(Theme.monoFont)
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .frame(width: widths[c], alignment: .leading)
                            .background(r % 2 == 1 ? Theme.gridStripe : .clear)
                            .border(Theme.gridLine, width: 0.5)
                    }
                }
            }
        }
    }

    private func gridWidths(header: [String], rows: [[String]]) -> [CGFloat] {
        header.indices.map { c in
            var maxLen = header[c].count
            for row in rows where c < row.count {
                maxLen = max(maxLen, min(row[c].count, 60))
            }
            return min(max(CGFloat(maxLen) * 7.3 + 20, 90), 420)
        }
    }
}
