import CoreGraphics
import Foundation

// MARK: - Value types

nonisolated struct ModuleLayoutItem: Identifiable, Equatable {
    var id: UUID
    var size: ModuleSize
}

nonisolated struct ModuleLayoutEntry: Identifiable, Equatable {
    var id: UUID
    var column: Int
    var span: Int
}

nonisolated struct ModuleLayoutRow: Identifiable, Equatable {
    var index: Int
    var entries: [ModuleLayoutEntry]

    var id: Int { index }
}

nonisolated struct ModulePlacement: Identifiable, Equatable {
    var id: UUID
    var row: Int
    var column: Int
    var span: Int
    var x: CGFloat
    var width: CGFloat
}

// MARK: - Engine

/// Deterministic, dependency-free adaptive grid.
///
/// Modules are packed in their persisted logical order. Each module declares a
/// size; the engine converts it to a column span for the current breakpoint and
/// starts a new row when the requested span no longer fits. It intentionally
/// does not use LazyVGrid or absolute window coordinates, so the same input
/// always produces the same placement and unit tests can verify it directly.
nonisolated enum WorkspaceLayoutEngine {
    static let spacing: CGFloat = 18
    static let minimumWidthForTwoColumns: CGFloat = 840
    static let minimumWidthForThreeColumns: CGFloat = 1180
    static let maximumColumns = 3
    static let maximumBoardWidth: CGFloat = 1500

    static func columnCount(for width: CGFloat) -> Int {
        if width >= minimumWidthForThreeColumns { return 3 }
        if width >= minimumWidthForTwoColumns { return 2 }
        return 1
    }

    static func placements(
        for items: [ModuleLayoutItem],
        columns: Int
    ) -> [ModulePlacement] {
        let columns = max(1, min(columns, maximumColumns))
        var result: [ModulePlacement] = []
        result.reserveCapacity(items.count)

        var row = 0
        var column = 0

        for item in items {
            let span = min(item.size.preferredSpan(columns: columns), columns)
            if column + span > columns {
                row += 1
                column = 0
            }
            result.append(ModulePlacement(
                id: item.id, row: row, column: column, span: span, x: 0, width: 0
            ))
            column += span
            if column >= columns {
                row += 1
                column = 0
            }
        }
        return result
    }

    static func rows(
        for items: [ModuleLayoutItem],
        columns: Int
    ) -> [ModuleLayoutRow] {
        let placements = placements(for: items, columns: columns)
        let maxRow = placements.map(\.row).max() ?? -1
        guard maxRow >= 0 else { return [] }

        return (0...maxRow).map { rowIndex in
            ModuleLayoutRow(
                index: rowIndex,
                entries: placements
                    .filter { $0.row == rowIndex }
                    .sorted { $0.column < $1.column }
                    .map { ModuleLayoutEntry(id: $0.id, column: $0.column, span: $0.span) }
            )
        }
    }

    static func entryWidth(
        span: Int,
        columns: Int,
        availableWidth: CGFloat,
        spacing: CGFloat = spacing
    ) -> CGFloat {
        let columns = max(1, min(columns, maximumColumns))
        let span = max(1, min(span, columns))
        let available = max(0, availableWidth)
        let totalGap = spacing * CGFloat(max(0, columns - 1))
        let columnWidth = max(0, (available - totalGap) / CGFloat(columns))
        return max(0, columnWidth * CGFloat(span) + spacing * CGFloat(span - 1))
    }

    static func placements(
        for items: [ModuleLayoutItem],
        availableWidth: CGFloat,
        spacing: CGFloat = spacing
    ) -> [ModulePlacement] {
        let width = min(max(0, availableWidth), maximumBoardWidth)
        let columns = columnCount(for: width)
        let base = placements(for: items, columns: columns)
        return base.map { placement in
            var value = placement
            value.width = entryWidth(span: placement.span, columns: columns,
                                     availableWidth: width, spacing: spacing)
            value.x = xOffset(for: placement, columns: columns,
                              availableWidth: width, spacing: spacing)
            return value
        }
    }

    private static func xOffset(
        for placement: ModulePlacement,
        columns: Int,
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard placement.column > 0 else { return 0 }
        let gap = entryWidth(span: 1, columns: columns,
                             availableWidth: availableWidth, spacing: spacing)
        return CGFloat(placement.column) * (gap + spacing)
    }

    /// Boards are capped at 1,500 points so a very wide display does not stretch
    /// paragraphs into unreadable lines. The caller still passes the raw measured
    /// width here; this helper is the single source of truth for that cap.
    static func contentWidth(for measuredWidth: CGFloat) -> CGFloat {
        min(max(0, measuredWidth), maximumBoardWidth)
    }
}