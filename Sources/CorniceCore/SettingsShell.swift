import SwiftUI

/// One row in the Options sidebar.
public struct SettingsSection: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let content: AnyView

    public init(id: String, title: String, systemImage: String, content: AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }
}

/// VS Code style Options window: sections on the left, one page on the right.
public struct SettingsShellView: View {
    private let sections: [SettingsSection]
    private let store: SettingsStore
    private let onPreview: (Bool) -> Void

    @State private var selection: String?
    @State private var pinned = false

    public init(
        sections: [SettingsSection],
        store: SettingsStore,
        onPreview: @escaping (Bool) -> Void
    ) {
        self.sections = sections
        self.store = store
        self.onPreview = onPreview
    }

    private var current: SettingsSection? {
        sections.first { $0.id == selection } ?? sections.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section.id)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            } detail: {
                ScrollView {
                    current?.content
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Text(Translator(store.settings.language)(
                    "Changes apply immediately.",
                    "Los cambios se aplican al instante."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Spacer()

                Button(
                    pinned
                        ? Translator(store.settings.language)("Hide notch", "Ocultar notch")
                        : Translator(store.settings.language)("Show notch", "Mostrar notch")
                ) {
                    pinned.toggle()
                    onPreview(pinned)
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 720, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selection == nil {
                selection = sections.first?.id
            }
        }
    }
}

// MARK: - Reusable form pieces

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

/// Slider bound to a settings key path, with its numeric readout.
struct SettingsSlider: View {
    let title: String
    let keyPath: WritableKeyPath<CorniceSettings, Double>
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    var hint: String?
    let store: SettingsStore

    var body: some View {
        let value = store.settings[keyPath: keyPath]

        VStack(alignment: .leading, spacing: 3) {
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
