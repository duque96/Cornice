import AppKit
import Observation
import SwiftUI
import CorniceKit

public struct MountedWidget: Identifiable {
    public let id: WidgetID
    public let name: String
    public let size: GridSize
    public let view: AnyView
    let widget: any CorniceWidget
}

/// Owns the widget lifecycle: mounting, activation and the single shared clock.
///
/// There is exactly one timer for every widget, and it only runs while the
/// surface is visible.
@Observable
@MainActor
public final class WidgetHost {
    public private(set) var widgets: [MountedWidget] = []

    private let factories: [any WidgetFactory.Type]
    private let keychain: any KeychainAccessing
    private let stageWidth: CGFloat
    private let log = WidgetLog(subsystem: "host")

    private var isActive = false
    private var ticker: Task<Void, Never>?

    public init(
        factories: [any WidgetFactory.Type],
        keychain: any KeychainAccessing = SystemKeychain(),
        stageWidth: CGFloat = 380
    ) {
        self.factories = factories
        self.keychain = keychain
        self.stageWidth = stageWidth
    }

    public func start() {
        guard widgets.isEmpty else { return }

        for factory in factories {
            let manifest = factory.manifest
            let problems = manifest.problems
            guard problems.isEmpty else {
                log.warn("skipping \(manifest.id): \(problems.joined(separator: ", "))")
                continue
            }

            let widgetLog = WidgetLog(subsystem: manifest.id)

            let scopedKeychain: (any KeychainAccessing)? = manifest.capabilities.contains(.keychain)
                ? ScopedKeychain(base: keychain, allowedServices: Set(manifest.keychainServices))
                : nil

            let http: (any HTTPClient)? = manifest.capabilities.contains(.network)
                ? WidgetHTTPClient(allowedHosts: Set(manifest.networkHosts), log: widgetLog)
                : nil

            let context = WidgetContext(
                capabilities: manifest.capabilities,
                keychain: scopedKeychain,
                http: http,
                log: widgetLog,
                availableWidth: stageWidth
            )

            let widget = factory.make(context: context)
            widgets.append(
                MountedWidget(
                    id: manifest.id,
                    name: manifest.name,
                    size: manifest.placement.size,
                    view: widget.makeView(),
                    widget: widget
                )
            )

            log.warn("mounted \(manifest.id) \(manifest.version)")
        }
    }

    public func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active

        for item in widgets {
            if active {
                item.widget.activate()
            } else {
                item.widget.deactivate()
            }
        }

        if active {
            startTicker()
        } else {
            stopTicker()
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }

                let now = Date()
                for item in self.widgets {
                    item.widget.tick(now)
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
