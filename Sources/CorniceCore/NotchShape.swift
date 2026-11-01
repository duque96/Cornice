import SwiftUI

/// The surface silhouette: flush with the top edge.
///
/// The top corners are *inverted*: the top edge spans the full width and the body
/// steps in, leaving a concave shoulder under each corner. The bottom corners are
/// convex.
public struct NotchShape: Shape, Animatable {
    /// Concave shoulder size. 0 gives square top corners.
    public var topFlare: CGFloat
    public var bottomRadius: CGFloat

    public init(topFlare: CGFloat = 0, bottomRadius: CGFloat = 12) {
        self.topFlare = topFlare
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFlare, bottomRadius) }
        set {
            topFlare = newValue.first
            bottomRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let flare = min(max(0, topFlare), min(rect.width, rect.height) / 2)
        let bottom = min(max(0, bottomRadius), min(rect.width, rect.height) / 2)

        // Full-width top edge, flush with the menu bar.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Inverted shoulder: the body steps in, the corner stays black.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare),
            control: CGPoint(x: rect.maxX - flare, y: rect.minY)
        )

        // Right side down to the convex bottom corner.
        path.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - flare - bottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX - flare, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.minX + flare + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + flare, y: rect.maxY - bottom),
            control: CGPoint(x: rect.minX + flare, y: rect.maxY)
        )

        // Left side up, then the mirrored shoulder into the top-left corner.
        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.minY + flare))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + flare, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
