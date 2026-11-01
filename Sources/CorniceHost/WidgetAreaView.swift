import SwiftUI
import CorniceKit

/// The stage: widgets placed on a grid, with page dots when they do not all fit.
public struct WidgetAreaView: View {
    private var host: WidgetHost

    @State private var pageIndex = 0

    public init(host: WidgetHost) {
        self.host = host
    }

    public var body: some View {
        GeometryReader { proxy in
            let pages = makePages(in: proxy.size)
            let index = min(pageIndex, max(0, pages.count - 1))

            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if host.widgets.isEmpty {
                        Text("No widgets installed")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    } else if !pages.isEmpty {
                        ForEach(pages[index].items) { item in
                            if let widget = byID[item.id] {
                                card(widget, frame: item.frame)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if pages.count > 1 {
                    dots(count: pages.count, selection: index)
                }
            }
        }
    }

    private var byID: [WidgetID: MountedWidget] {
        Dictionary(uniqueKeysWithValues: host.widgets.map { ($0.id, $0) })
    }

    private func makePages(in size: CGSize) -> [WidgetGridLayout.Page] {
        let dotsHeight: CGFloat = host.widgets.count > 0 ? 14 : 0
        let available = CGSize(
            width: size.width,
            height: max(0, size.height - dotsHeight)
        )

        return WidgetGridLayout.layout(
            widgets: host.widgets.map {
                WidgetGridLayout.Widget(id: $0.id, size: $0.size)
            },
            available: available
        )
    }

    private func card(_ widget: MountedWidget, frame: CGRect) -> some View {
        widget.view
            .padding(12)
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
            }
            .position(x: frame.midX, y: frame.midY)
    }

    private func dots(count: Int, selection: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    pageIndex = index
                } label: {
                    Circle()
                        .fill(Color.white.opacity(index == selection ? 0.7 : 0.22))
                        .frame(width: 4, height: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 10)
    }
}
