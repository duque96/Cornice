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
        let t = Translator(store.settings.language)

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("General", "General"))
                    .font(.system(size: 17, weight: .semibold))
                Text(t("How Cornice shows up on your Mac.", "Cómo se muestra Cornice en tu Mac."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: t("Language", "Idioma")) {
                Picker(
                    t("Language", "Idioma"),
                    selection: Binding(
                        get: { store.settings.language },
                        set: { store.set(\.language, $0) }
                    )
                ) {
                    Text(t("System", "Sistema")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.en)
                    Text("Español").tag(AppLanguage.es)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            SettingsGroup(title: t("Menu bar", "Barra de menús")) {
                Toggle(
                    t("Show menu bar icon", "Mostrar icono en la barra de menús"),
                    isOn: Binding(
                        get: { store.settings.showMenuBarIcon },
                        set: { store.set(\.showMenuBarIcon, $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text(t(
                    "When off, the app only lives in the notch. Open Options from the gear inside the panel.",
                    "Si lo desactivas, la app solo vive en el notch. Abre Opciones desde el engranaje del panel."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Quit Cornice", "Salir de Cornice"))
                        .font(.system(size: 12))
                    Text(t("Stops the notch surface and its widgets.", "Detiene la superficie y sus widgets."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("Quit", "Salir"), role: .destructive, action: onQuit)
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
        let t = Translator(store.settings.language)

        VStack(alignment: .leading, spacing: 22) {
            header(
                t("Motion", "Movimiento"),
                t("How the surface grows and collapses.", "Cómo crece y se contrae la superficie.")
            )

            SettingsGroup(title: t("Opening", "Apertura")) {
                SettingsSlider(
                    title: t("Response", "Respuesta"),
                    keyPath: \.motion.openResponse,
                    range: 0.10...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    hint: t("Higher is slower.", "Más alto, más lento."),
                    store: store
                )
                SettingsSlider(
                    title: t("Bounce", "Rebote"),
                    keyPath: \.motion.openDamping,
                    range: 0.55...1.00,
                    step: 0.01,
                    format: "%.2f",
                    hint: t("1.00 is dead flat. Lower overshoots.", "1.00 es plano. Menos rebota."),
                    store: store
                )
            }

            SettingsGroup(title: t("Closing", "Cierre")) {
                SettingsSlider(
                    title: t("Response", "Respuesta"),
                    keyPath: \.motion.closeResponse,
                    range: 0.10...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    store: store
                )
                SettingsSlider(
                    title: t("Bounce", "Rebote"),
                    keyPath: \.motion.closeDamping,
                    range: 0.55...1.00,
                    step: 0.01,
                    format: "%.2f",
                    store: store
                )
            }

            SettingsGroup(title: t("Content", "Contenido")) {
                SettingsSlider(
                    title: t("Fade delay", "Retardo del fundido"),
                    keyPath: \.motion.contentDelay,
                    range: 0...0.60,
                    step: 0.01,
                    format: "%.2f s",
                    hint: t(
                        "How long the silhouette grows before the content appears.",
                        "Cuánto crece la silueta antes de mostrar el contenido."
                    ),
                    store: store
                )
                SettingsSlider(
                    title: t("Fade duration", "Duración del fundido"),
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
        let t = Translator(store.settings.language)

        VStack(alignment: .leading, spacing: 22) {
            header(
                t("Interaction", "Interacción"),
                t(
                    "When the surface opens and closes around the pointer.",
                    "Cuándo se abre y se cierra alrededor del puntero."
                )
            )

            SettingsGroup(title: t("Pointer", "Puntero")) {
                SettingsSlider(
                    title: t("Open delay", "Retardo de apertura"),
                    keyPath: \.hoverOpenDelay,
                    range: 0...0.50,
                    step: 0.01,
                    format: "%.2f s",
                    hint: t(
                        "Rest time in the hot zone before opening.",
                        "Tiempo de reposo en la zona antes de abrir."
                    ),
                    store: store
                )
                SettingsSlider(
                    title: t("Close delay", "Retardo de cierre"),
                    keyPath: \.hoverCloseDelay,
                    range: 0.05...0.80,
                    step: 0.01,
                    format: "%.2f s",
                    hint: t(
                        "Grace period before collapsing when the pointer leaves.",
                        "Margen antes de cerrarse cuando el puntero sale."
                    ),
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
        let t = Translator(store.settings.language)

        VStack(alignment: .leading, spacing: 22) {
            header(
                t("Panel", "Panel"),
                t(
                    "Size of the expanded surface. Widgets page when they do not fit.",
                    "Tamaño de la superficie expandida. Los widgets pasan a otra página si no caben."
                )
            )

            SettingsGroup(title: t("Size", "Tamaño")) {
                Toggle(
                    t("Fit to content", "Ajustar al contenido"),
                    isOn: Binding(
                        get: { store.settings.fitToContent },
                        set: { store.set(\.fitToContent, $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text(t(
                    "The panel hugs the tallest page and the height below is ignored.",
                    "El panel se ajusta a la página más alta; la altura de abajo se ignora."
                ))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                SettingsSlider(
                    title: t("Width", "Ancho"),
                    keyPath: \.expandedWidth,
                    range: 280...760,
                    step: 10,
                    format: "%.0f pt",
                    store: store
                )

                SettingsSlider(
                    title: t("Height", "Alto"),
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
                    Text(t("Restore defaults", "Restaurar valores"))
                        .font(.system(size: 12))
                    Text(t("Resets motion, timing and size.", "Restablece movimiento, tiempos y tamaño."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("Restore", "Restaurar")) {
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
