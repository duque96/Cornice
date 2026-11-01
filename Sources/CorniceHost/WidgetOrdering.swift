import Foundation
import CorniceKit

/// Pure ordering rules, so the drag behaviour can be tested without UI.
public enum WidgetOrdering {
    /// IDs listed in `order` come first, in that order; the rest keep their
    /// original relative position.
    public static func sorted(_ ids: [WidgetID], by order: [WidgetID]) -> [WidgetID] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        return ids.enumerated().sorted { lhs, rhs in
            switch (rank[lhs.element], rank[rhs.element]) {
            case let (left?, right?):
                return left == right ? lhs.offset < rhs.offset : left < right
            case (nil, nil):
                return lhs.offset < rhs.offset
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }.map(\.element)
    }

    /// Moves `id` to the slot currently occupied by `target`.
    public static func moving(
        _ id: WidgetID,
        before target: WidgetID,
        in ids: [WidgetID]
    ) -> [WidgetID] {
        guard id != target, let from = ids.firstIndex(of: id) else { return ids }

        var result = ids
        result.remove(at: from)

        guard let to = result.firstIndex(of: target) else { return ids }
        result.insert(id, at: to)
        return result
    }
}
