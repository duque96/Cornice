import SwiftUI
import CorniceKit

/// Options page for a single widget, generated from its manifest.
public struct WidgetSettingsView: View {
    private let host: WidgetHost
    private let widgetID: WidgetID

    public init(host: WidgetHost, widgetID: WidgetID) {
        self.host = host
        self.widgetID = widgetID
    }

    public var body: some View {
        if let manifest = host.manifest(for: widgetID) {
            VStack(alignment: .leading, spacing: 20) {
                header(manifest)

                if manifest.settings.isEmpty {
                    Text("This widget has no options.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(manifest.settings) { setting in
                            row(setting)
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Text(manifest.capabilities.map(\.rawValue).sorted().joined(separator: " · "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(manifest.id)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("Widget not found")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func header(_ manifest: WidgetManifest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(manifest.name)
                    .font(.system(size: 17, weight: .semibold))
                Text(manifest.version.description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("Changes are saved to Application Support and reload the widget.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ setting: WidgetSetting) -> some View {
        switch setting.kind {
        case .toggle:
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: boolBinding(setting)) {
                    Text(setting.title)
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if let description = setting.description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

        case .number(let lower, let upper, let step):
            let binding = numberBinding(setting)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(setting.title)
                        .font(.system(size: 12))
                    Spacer()
                    Text(String(format: "%.0f", binding.wrappedValue))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(value: binding, in: lower...upper, step: step)

                if let description = setting.description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

        case .text(let placeholder):
            VStack(alignment: .leading, spacing: 3) {
                Text(setting.title)
                    .font(.system(size: 12))
                TextField(placeholder ?? "", text: stringBinding(setting))
                    .textFieldStyle(.roundedBorder)
                if let description = setting.description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

        case .select(let options):
            VStack(alignment: .leading, spacing: 3) {
                Picker(setting.title, selection: stringBinding(setting)) {
                    ForEach(options, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }

                if let description = setting.description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Bindings

    private func currentValue(_ setting: WidgetSetting) -> SettingValue {
        host.settingsValues(for: widgetID)[setting.id] ?? setting.defaultValue
    }

    private func boolBinding(_ setting: WidgetSetting) -> Binding<Bool> {
        Binding(
            get: { currentValue(setting).boolValue ?? false },
            set: { host.setSetting(widgetID, key: setting.id, value: .bool($0)) }
        )
    }

    private func numberBinding(_ setting: WidgetSetting) -> Binding<Double> {
        Binding(
            get: { currentValue(setting).numberValue ?? 0 },
            set: { host.setSetting(widgetID, key: setting.id, value: .number($0)) }
        )
    }

    private func stringBinding(_ setting: WidgetSetting) -> Binding<String> {
        Binding(
            get: { currentValue(setting).stringValue ?? "" },
            set: { host.setSetting(widgetID, key: setting.id, value: .string($0)) }
        )
    }
}
