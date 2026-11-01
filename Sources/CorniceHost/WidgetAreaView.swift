import SwiftUI
import CorniceCore
import CorniceKit

/// The stage: widgets placed on a grid, with interactive page dragging.
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
            let pageHeight = max(0, proxy.size.height - (pages.count > 1 ? 14 : 0))
            let width = proxy.size.width

            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if host.widgets.isEmpty {
                        Text("No widgets installed")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    } else if !pages.isEmpty {
                        ForEach(visiblePages(pages.count, index: index), id: \.self) { pageIndex in
                            pageView(pages[pageIndex], width: width, height: pageHeight)
                                .frame(width: width, height: pageHeight, alignment: .topLeading)
                                .offset(x: CGFloat(pageIndex - index) * width + pager.offset)
                        }
                    }
                }
                .frame(width: width, height: pageHeight, alignment: .topLeading)
                .clipped()

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

    /// Mount the neighbouring pages only while dragging, so they can slide in.
    private func visiblePages(_ count: Int, index: Int) -> [Int] {
        guard pager.isDragging else { return [index] }
        return [index - 1, index, index + 1].filter { $0 >= 0 && $0 < count }
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

    private func pageView(
        _ page: WidgetGridLayout.Page,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(page.items) { item in
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
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func dots(count: Int, selection: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                        pager.select(index)
                    }
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
