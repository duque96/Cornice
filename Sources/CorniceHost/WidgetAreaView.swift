import SwiftUI
import CorniceCore
import CorniceKit

/// The stage: widgets placed on a grid, with page dots when they do not all fit.
///
/// No card chrome: the panel's black is the background, like the rest of the
/// notch-app ecosystem. Widgets are separated by spacing, not by frames.
public struct WidgetAreaView: View {
    private var host: WidgetHost
    private var pager: StagePager

    public init(host: WidgetHost, pager: StagePager = StagePager()) {
        self.host = host
        self.pager = pager
    }

    public var body: some View {
        GeometryReader { proxy in
            let pages = makePages(in: proxy.size)
            let index = min(pager.index, max(0, pages.count - 1))

            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if host.widgets.isEmpty {
                        Text("No widgets installed")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    } else if !pages.isEmpty {
                        ForEach(pages[index].items) { item in
                            if let widget = byID[item.id] {
                                widget.view
                                    .padding(8)
                                    .frame(
                                        width: item.frame.width,
                                        height: item.frame.height,
                                        alignment: .topLeading
                                    )
                                    .position(x: item.frame.midX, y: item.frame.midY)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if pages.count > 1 {
                    dots(count: pages.count, selection: index)
                }
            }
            .onAppear { pager.setPageCount(pages.count) }
            .onChange(of: pages.count) { _, count in
                pager.setPageCount(count)
            }
        }
    }

    private var byID: [WidgetID: MountedWidget] {
        Dictionary(uniqueKeysWithValues: host.widgets.map { ($0.id, $0) })
    }

    /// Dots take space only when there is more than one page, so a single page
    /// gets the full height.
    private func makePages(in size: CGSize) -> [WidgetGridLayout.Page] {
        let widgets = host.widgets.map {
            WidgetGridLayout.Widget(id: $0.id, size: $0.size)
        }

        let full = WidgetGridLayout.layout(widgets: widgets, available: size)
        guard full.count > 1 else { return full }

        return WidgetGridLayout.layout(
            widgets: widgets,
            available: CGSize(width: size.width, height: max(0, size.height - 14))
        )
    }

    private func dots(count: Int, selection: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    pager.index = index
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
