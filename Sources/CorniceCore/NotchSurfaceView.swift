import SwiftUI

/// M0 placeholder: proves the surface, says where widgets will land.
///
/// Layout rule: the silhouette animates, the content never reflows. The content is
/// laid out once at its final size and revealed by a mask, so nothing gets squeezed
/// while the spring is running.
struct NotchSurfaceView: View {
    var model: NotchSurfaceModel
    /// Test-only: renders the surface at a fixed point of the transition.
    /// Production always drives this from `model.state`.
    var previewProgress: Double? = nil

    private var open: Bool { model.state == .open }
    private var progress: Double { previewProgress ?? (open ? 1 : 0) }
    private var size: CGSize {
        CGSize(
            width: lerp(model.notchSize.width, model.expandedSize.width),
            height: lerp(model.notchSize.height, model.expandedSize.height)
        )
    }
    private var topRadius: CGFloat { lerp(model.notchCornerRadius, 10) }
    private var bottomRadius: CGFloat { lerp(model.notchCornerRadius, 24) }
    private var contentOpacity: Double {
        guard previewProgress != nil else { return open ? 1 : 0 }
        return max(0, min(1, (progress - 0.9) / 0.1))
    }
    private var animation: Animation { open ? model.motion.open : model.motion.close }

    private func lerp(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + (to - from) * CGFloat(progress)
    }

    var body: some View {
        ZStack(alignment: .top) {
            silhouette

            content
                .mask(alignment: .top) { maskShape }
                .opacity(contentOpacity)
                .scaleEffect(open ? 1 : 0.985, anchor: .top)
                .animation(open ? model.motion.contentIn : model.motion.contentOut, value: open)
        }
        .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var silhouette: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay {
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .stroke(Color.white.opacity(open ? 0.07 : 0), lineWidth: 1)
            }
            .animation(animation, value: open)
    }

    /// Same geometry as the silhouette, but padded to the full panel so the mask
    /// itself never changes the content's layout.
    private var maskShape: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .frame(width: size.width, height: size.height)
            .animation(animation, value: open)
            .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text("Cornice")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Text("M0")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(Color.white.opacity(0.65))

                Spacer(minLength: 0)

                Text(model.mode.rawValue)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))

                Button {
                    model.onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            Text("The notch is live. Widgets land here in M3.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))

            HStack(spacing: 10) {
                placeholderTile("Now Playing")
                placeholderTile("Calendar")
                placeholderTile("Shelf")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
    }

    private func placeholderTile(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }
}
