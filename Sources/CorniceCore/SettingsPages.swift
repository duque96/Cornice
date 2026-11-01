import SwiftUI

// MARK: - General

public struct GeneralSettingsView: View {
    private let store: SettingsStore
    private let onQuit: () -> Void

    public init(store: SettingsStore, onQuit: @escaping () -> Void) {
        self.store = store
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("General")
                    .font(.system(size: 17, weight: .semibold))
                Text("How Cornice shows up on your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: "Menu bar") {
                Toggle(
                    "Show menu bar icon",
                    isOn: Binding(
                        get: { store.settings.showMenuBarIcon },
                        set: { store.set(\.showMenuBarIcon, $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("When off, the app only lives in the notch. Open Options from the gear inside the panel.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quit Cornice")
                        .font(.system(size: 12))
                    Text("Stops the notch surface and its widgets.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit", role: .destructive, action: onQuit)
            }
        }
    }
}

// MARK: - Motion

public struct MotionSettingsView: View {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header(
                "Motion",
                "How the surface grows and collapses."
            )

            SettingsGroup(title: "Opening") {
                SettingsSlider(
                    title: "Response",
                    keyPath: \.motion.openResponse,
                    range: 0.10...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "Higher is slower.",
                    store: store
                )
                SettingsSlider(
                    title: "Bounce",
                    keyPath: \.motion.openDamping,
                    range: 0.55...1.00,
                    step: 0.01,
                    format: "%.2f",
                    hint: "1.00 is dead flat. Lower overshoots.",
                    store: store
                )
            }

            SettingsGroup(title: "Closing") {
                SettingsSlider(
                    title: "Response",
                    keyPath: \.motion.closeResponse,
                    range: 0.10...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    store: store
                )
                SettingsSlider(
                    title: "Bounce",
                    keyPath: \.motion.closeDamping,
                    range: 0.55...1.00,
                    step: 0.01,
                    format: "%.2f",
                    store: store
                )
            }

            SettingsGroup(title: "Content") {
                SettingsSlider(
                    title: "Fade delay",
                    keyPath: \.motion.contentDelay,
                    range: 0...0.60,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "How long the silhouette grows before the content appears.",
                    store: store
                )
                SettingsSlider(
                    title: "Fade duration",
                    keyPath: \.motion.contentDuration,
                    range: 0.05...0.50,
                    step: 0.01,
                    format: "%.2f s",
                    store: store
                )
            }
        }
    }
}

// MARK: - Interaction

public struct InteractionSettingsView: View {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header(
                "Interaction",
                "When the surface opens and closes around the pointer."
            )

            SettingsGroup(title: "Pointer") {
                SettingsSlider(
                    title: "Open delay",
                    keyPath: \.hoverOpenDelay,
                    range: 0...0.50,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "Rest time in the hot zone before opening.",
                    store: store
                )
                SettingsSlider(
                    title: "Close delay",
                    keyPath: \.hoverCloseDelay,
                    range: 0.05...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    hint: "Grace period before collapsing when the pointer leaves.",
                    store: store
                )
            }
        }
    }
}

// MARK: - Panel

public struct PanelSettingsView: View {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header(
                "Panel",
                "Size of the expanded surface. Widgets scroll when they do not fit."
            )

            SettingsGroup(title: "Size") {
                Toggle(
                    "Fit to content",
                    isOn: Binding(
                        get: { store.settings.fitToContent },
                        set: { store.set(\.fitToContent, $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("The panel hugs the tallest page and the height below is ignored.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                SettingsSlider(
                    title: "Width",
                    keyPath: \.expandedWidth,
                    range: 280...760,
                    step: 10,
                    format: "%.0f pt",
                    store: store
                )

                SettingsSlider(
                    title: "Height",
                    keyPath: \.expandedHeight,
                    range: 120...320,
                    step: 5,
                    format: "%.0f pt",
                    store: store
                )
                .disabled(store.settings.fitToContent)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore defaults")
                        .font(.system(size: 12))
                    Text("Resets motion, timing and size.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore") {
                    store.reset()
                }
            }
        }
    }
}

// MARK: - Shared

private func header(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
        Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}
