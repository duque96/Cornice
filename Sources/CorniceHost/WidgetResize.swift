import Foundation
import CorniceKit

/// Turns a corner drag into a grid size. Pure so the snapping can be tested.
public enum WidgetResize {
    public static let maxRows = 8

    public static func snapped(
        start: GridSize,
        translation: CGSize,
        columnWidth: CGFloat,
        rowUnit: CGFloat,
        gap: CGFloat,
        maxColumns: Int = WidgetGridLayout.columns
    ) -> GridSize {
        guard columnWidth > 0, rowUnit > 0 else { return start }

        let startWidth = columnWidth * CGFloat(start.columns) + gap * CGFloat(start.columns - 1)
        let startHeight = rowUnit * CGFloat(start.rows) + gap * CGFloat(start.rows - 1)

        let width = startWidth + translation.width
        let height = startHeight + translation.height

        let columns = Int(((width + gap) / (columnWidth + gap)).rounded())
        let rows = Int(((height + gap) / (rowUnit + gap)).rounded())

        return GridSize(
            columns: min(max(1, columns), maxColumns),
            rows: min(max(1, rows), maxRows)
        )
    }
}
