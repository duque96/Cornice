import SwiftUI
import CorniceCore
import CorniceKit

/// Visual grid editor: drag a widget's corner to change its span.
public struct LayoutEditorView: View {
    private let host: WidgetHost

    private let canvasWidth: CGFloat = 380

    public init(host: WidgetHost) {
        self.host = host
    }

    private var columnWidth: CGFloat {
        (canvasWidth - WidgetGridLayout.gap * CGFloat(WidgetGridLayout.columns - 1))
            / CGFloat(WidgetGridLayout.columns)
    }

    public var body: some View {
        let t = Translator(host.language)

        VStack(alignment: .leading, spacing: 18) {
            header

            if host.catalog.isEmpty {
                Text(t("Enable a widget first.", "Activa un widget primero."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                canvas
            }

            HStack {
                Text(t(
                    "Drag the corner handle. Sizes snap to columns and rows.",
                    "Arrastra la esquina. El tamaño se ajusta a columnas y filas."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                Spacer()
                Button(t("Reset sizes", "Restablecer tamaños")) {
                    host.resetSizes()
                }
                .controlSize(.small)
            }
        }
    }

    private var header: some View {
        let t = Translator(host.language)

        return VStack(alignment: .leading, spacing: 4) {
            Text(t("Layout", "Disposición"))
                .font(.system(size: 17, weight: .semibold))
            Text(t(
                "Six columns, 30 pt rows. Widgets page when they do not fit.",
                "Seis columnas, filas de 30 pt. Los widgets pasan a otra página si no caben."
            ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var canvas: some View {
        let pages = WidgetGridLayout.layout(
            widgets: host.catalog.map {
                WidgetGridLayout.Widget(id: $0.id, size: $0.size)
            },
            available: CGSize(width: canvasWidth, height: 4_000)
        )
        let items = pages.first?.items ?? []
        let height = max(60, (items.map(\.frame.maxY).max() ?? 0) + WidgetGridLayout.gap)

        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                if let entry = host.catalog.first(where: { $0.id == item.id }) {
                    tile(entry, frame: item.frame)
                }
            }
        }
        .frame(width: canvasWidth, height: height, alignment: .topLeading)
    }

    private func tile(_ entry: WidgetCatalogEntry, frame: CGRect) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(entry.enabled ? 0.10 : 0.04))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text("\(entry.size.columns) × \(entry.size.rows)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)

            ResizeHandle(entry: entry, columnWidth: columnWidth, host: host)
                .padding(4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
}

private struct ResizeHandle: View {
    let entry: WidgetCatalogEntry
    let columnWidth: CGFloat
    let host: WidgetHost

    @State private var startSize: GridSize?

    var body: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if startSize == nil {
                            startSize = entry.size
                        }
                        guard let start = startSize else { return }

                        let size = WidgetResize.snapped(
                            start: start,
                            translation: value.translation,
                            columnWidth: columnWidth,
                            rowUnit: WidgetGridLayout.rowUnit,
                            gap: WidgetGridLayout.gap
                        )
                        host.setSize(size, for: entry.id, persist: false)
                    }
                    .onEnded { _ in
                        host.persistSize(for: entry.id)
                        startSize = nil
                    }
            )
            .help(Translator(host.language)("Drag to resize", "Arrastra para redimensionar"))
    }
}
