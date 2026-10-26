import SwiftUI

/// M0 placeholder: proves the surface, says where widgets will land.
struct NotchSurfaceView: View {
    @Bindable var model: NotchSurfaceModel

    private var open: Bool { model.state == .open }

    var body: some View {
        VStack(spacing: 0) {
            surface
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var surface: some View {
        let topRadius = open ? 10 : model.notchCornerRadius
        let bottomRadius = open ? 24 : model.notchCornerRadius

        return ZStack(alignment: .topLeading) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)

            content
                .opacity(open ? 1 : 0)
        }
        .frame(
            width: model.surfaceSize.width,
            height: model.surfaceSize.height,
            alignment: .top
        )
        .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .overlay {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .stroke(Color.white.opacity(open ? 0.08 : 0), lineWidth: 1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: model.state)
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
            }

            Text("The notch is live. Widgets land here in M3.")
                .font(.system(size: 11, weight: .regular))
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
