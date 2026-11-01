import Foundation
import CorniceKit

/// Places widgets on a 6-column grid, paginating when a column of rows overflows.
///
/// Pure and deterministic: no SwiftUI, no AppKit. The view just renders the frames.
public enum WidgetGridLayout {
    public static let columns = 6
    public static let rowUnit: CGFloat = 30
    public static let gap: CGFloat = 8

    public struct Item: Identifiable, Equatable {
        public let id: WidgetID
        public let frame: CGRect

        public init(id: WidgetID, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    public struct Page: Equatable {
        public let items: [Item]
    }

    public struct Widget: Equatable {
        public let id: WidgetID
        public let size: GridSize
        public let priority: Int

        public init(id: WidgetID, size: GridSize, priority: Int = 0) {
            self.id = id
            self.size = size
            self.priority = priority
        }
    }

    public static func layout(widgets: [Widget], available: CGSize) -> [Page] {
        guard !widgets.isEmpty, available.width > 0, available.height > 0 else { return [] }

        let columnWidth = max(1, (available.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let ordered = widgets.enumerated().sorted { lhs, rhs in
            lhs.element.priority == rhs.element.priority
                ? lhs.offset < rhs.offset
                : lhs.element.priority > rhs.element.priority
        }.map(\.element)

        var pages: [Page] = []
        var items: [Item] = []

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        func closePage() {
            guard !items.isEmpty else { return }
            pages.append(Page(items: items))
            items = []
            x = 0
            y = 0
            rowHeight = 0
        }

        for widget in ordered {
            let span = min(max(1, widget.size.columns), columns)
            let rows = max(1, widget.size.rows)

            let width = columnWidth * CGFloat(span) + gap * CGFloat(span - 1)
            let height = min(
                rowUnit * CGFloat(rows) + gap * CGFloat(rows - 1),
                available.height
            )

            // Wrap to the next row when it does not fit on the current line.
            if x > 0 && x + width > available.width + 0.5 {
                x = 0
                y += rowHeight + gap
                rowHeight = 0
            }

            // New page when the row would overflow the bottom.
            if y + height > available.height + 0.5 && !items.isEmpty {
                closePage()
            }

            items.append(
                Item(
                    id: widget.id,
                    frame: CGRect(x: x, y: y, width: width, height: height)
                )
            )

            x += width + gap
            rowHeight = max(rowHeight, height)
        }

        closePage()
        return pages
    }
}
