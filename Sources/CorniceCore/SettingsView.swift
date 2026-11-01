import SwiftUI

/// Options window: every value the surface uses is editable here.
struct SettingsView: View {
    var store: SettingsStore
    var onPreview: (Bool) -> Void
    var widgetsSection: AnyView? = nil

    @State private var pinned = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                SettingsForm(store: store, widgetsSection: widgetsSection)
                    .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Restore defaults") {
                    store.reset()
                }

                Spacer()

                Button(pinned ? "Hide notch" : "Show notch") {
                    pinned.toggle()
                    onPreview(pinned)
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
            .padding(16)
        }
        .frame(width: 540, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The scrollable part, split out so it can be rendered and reviewed on its own.
struct SettingsForm: View {
    var store: SettingsStore
    var widgetsSection: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            introduction

            group("Opening") {
                slider(
                    "Response",
                    \.motion.openResponse,
                    range: 0.10...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "Higher is slower."
                )
                slider(
                    "Bounce",
                    \.motion.openDamping,
                    range: 0.55...1.00,
                    step: 0.01,
                    format: "%.2f",
                    hint: "1.00 is dead flat. Lower overshoots."
                )
            }

            group("Closing") {
                slider(
                    "Response",
                    \.motion.closeResponse,
                    range: 0.10...0.80,
                    step: 0.01,
                    format: "%.2f s"
                )
                slider(
                    "Bounce",
                    \.motion.closeDamping,
                    range: 0.55...1.00,
                    step: 0.01,
                    format: "%.2f"
                )
            }

            group("Content") {
                slider(
                    "Fade delay",
                    \.motion.contentDelay,
                    range: 0...0.60,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "How long the silhouette grows before the content appears."
                )
                slider(
                    "Fade duration",
                    \.motion.contentDuration,
                    range: 0.05...0.50,
                    step: 0.01,
                    format: "%.2f s"
                )
            }

            group("Interaction") {
                slider(
                    "Open delay",
                    \.hoverOpenDelay,
                    range: 0...0.50,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "Rest time in the hot zone before opening."
                )
                slider(
                    "Close delay",
                    \.hoverCloseDelay,
                    range: 0.05...0.80,
                    step: 0.01,
                    format: "%.2f s"
                )
            }

            group("Panel size") {
                slider(
                    "Width",
                    \.expandedWidth,
                    range: 280...760,
                    step: 10,
                    format: "%.0f pt"
                )
                slider(
                    "Height",
                    \.expandedHeight,
                    range: 120...320,
                    step: 5,
                    format: "%.0f pt"
                )
            }

            if let widgetsSection {
                group("Widgets") {
                    widgetsSection
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cornice settings")
                .font(.system(size: 17, weight: .semibold))
            Text("Changes apply immediately and are saved to Application Support.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<CorniceSettings, Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        hint: String? = nil
    ) -> some View {
        let value = store.settings[keyPath: keyPath]

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { store.settings[keyPath: keyPath] },
                    set: { store.set(keyPath, $0) }
                ),
                in: range,
                step: step
            )

            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
