import SwiftUI

struct ERTableNodeView: View {
    let node: ERTableNode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            columnList
        }
        .frame(width: ERDiagramLayout.nodeWidth)
        .background(Color(nsColor: ThemeEngine.shared.colors.sidebar.background))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: ThemeEngine.shared.colors.ui.border), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tablecells")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(node.tableName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text("\(node.displayColumns.count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Column List

    private var columnList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if node.displayColumns.isEmpty {
                Text("No columns")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(node.displayColumns) { col in
                    columnRow(col)
                }
            }
        }
    }

    private func columnRow(_ col: ERColumnDisplay) -> some View {
        HStack(spacing: 4) {
            if col.isPrimaryKey {
                Image(systemName: "key.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                    .frame(width: 14)
            } else if col.isForeignKey {
                Image(systemName: "link")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            Text(col.name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Text(col.dataType)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if col.isNullable {
                Text("?")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
