import SwiftUI
import CorniceKit

/// The stage: the widgets the host has mounted, stacked.
public struct WidgetAreaView: View {
    private var host: WidgetHost

    public init(host: WidgetHost) {
        self.host = host
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(host.widgets) { item in
                card(item)
            }

            if host.widgets.isEmpty {
                Text("No widgets installed")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private func card(_ item: MountedWidget) -> some View {
        item.view
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
            }
    }
}
