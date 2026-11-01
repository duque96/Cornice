import SwiftUI
import CorniceKit

/// The widget list shown inside Options.
public struct WidgetGalleryView: View {
    private var host: WidgetHost
    private let onRevealFolder: () -> Void

    @State private var dropTarget: WidgetID?

    public init(host: WidgetHost, onRevealFolder: @escaping () -> Void) {
        self.host = host
        self.onRevealFolder = onRevealFolder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(host.catalog) { entry in
                row(entry)
            }

            ForEach(host.discoveryErrors, id: \.self) { error in
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Open widgets folder", action: onRevealFolder)
                Button("Reload") { host.reload() }
                Spacer()
                Text("Drag rows to reorder · drop bundles in the folder")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
    }

    private func row(_ entry: WidgetCatalogEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(entry.version.description)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(entry.source == .disk ? "disk" : "built-in")
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Text(
                    entry.capabilities.map(\.rawValue).sorted().joined(separator: " · ")
                        .isEmpty ? "no capabilities" : entry.capabilities.map(\.rawValue).sorted().joined(separator: " · ")
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Toggle(
                "",
                isOn: Binding(
                    get: { host.isEnabled(entry.id) },
                    set: { host.setEnabled(entry.id, $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dropTarget == entry.id ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .contentShape(Rectangle())
        .draggable(entry.id) {
            Text(entry.name)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            host.move(dragged, before: entry.id)
            dropTarget = nil
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTarget = entry.id
            } else if dropTarget == entry.id {
                dropTarget = nil
            }
        }
    }
}
