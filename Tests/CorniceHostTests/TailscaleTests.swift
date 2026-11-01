import SwiftUI
import XCTest
@testable import CorniceHost
@testable import CorniceCore
@testable import CorniceKit

private struct FakeTailscale: TailscaleControlling {
    func status() async -> TailscaleStatus? {
        TailscaleStatus(
            backendState: "Running",
            hostname: "MacBook",
            ip: "100.64.0.5",
            peersOnline: 1,
            peersTotal: 4
        )
    }

    func setEnabled(_ enabled: Bool) async -> Result<Void, TailscaleError> {
        .success(())
    }
}

@MainActor
private final class TailscaleProbe: CorniceWidget {
    let context: WidgetContext

    init(context: WidgetContext) {
        self.context = context
    }

    func makeView() -> AnyView { AnyView(EmptyView()) }
    func activate() {}
    func deactivate() {}
    func tick(_ now: Date) {}
}

@MainActor
private final class ProbeBox {
    var contexts: [WidgetContext] = []
}

@MainActor
private struct ProbeFactory: WidgetFactory {
    let manifest: WidgetManifest
    let box: ProbeBox

    func make(context: WidgetContext) -> any CorniceWidget {
        box.contexts.append(context)
        return TailscaleProbe(context: context)
    }
}

final class TailscaleTests: XCTestCase {
    func testParsesTheCliStatus() throws {
        let json = """
        {
          "Version": "1.102.3",
          "BackendState": "Running",
          "TailscaleIPs": ["100.64.0.5", "fd7a:115c:a1e0::5"],
          "Self": { "HostName": "MacBook Air de Daniel" },
          "Peer": {
            "a": { "Online": true },
            "b": { "Online": false },
            "c": { "Online": true }
          }
        }
        """

        let status = try XCTUnwrap(SystemTailscale.parse(Data(json.utf8)))

        XCTAssertEqual(status.backendState, "Running")
        XCTAssertEqual(status.ip, "100.64.0.5")
        XCTAssertEqual(status.hostname, "MacBook Air de Daniel")
        XCTAssertEqual(status.peersOnline, 2)
        XCTAssertEqual(status.peersTotal, 3)
        XCTAssertTrue(status.isConnected)
    }

    func testRejectsGarbage() {
        XCTAssertNil(SystemTailscale.parse(Data("not json".utf8)))
        XCTAssertNil(SystemTailscale.parse(Data("{}".utf8)))
    }

    @MainActor
    func testCapabilityGatesTheController() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-ts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let box = ProbeBox()

        let withCapability = ProbeFactory(
            manifest: WidgetManifest(
                id: "com.example.with-tailscale",
                name: "With",
                version: SemanticVersion(1, 0, 0),
                capabilities: [.tailscale],
                placement: Placement(size: GridSize(columns: 1, rows: 1))
            ),
            box: box
        )

        let without = ProbeFactory(
            manifest: WidgetManifest(
                id: "com.example.without-tailscale",
                name: "Without",
                version: SemanticVersion(1, 0, 0),
                placement: Placement(size: GridSize(columns: 1, rows: 1))
            ),
            box: box
        )

        let host = WidgetHost(
            factories: [withCapability, without],
            widgetsDirectory: root.appendingPathComponent("Widgets", isDirectory: true),
            preferences: WidgetPreferencesStore(url: root.appendingPathComponent("widgets.json")),
            settingsStore: WidgetSettingsStore(root: root.appendingPathComponent("settings")),
            tailscale: FakeTailscale()
        )
        host.start()

        XCTAssertEqual(box.contexts.count, 2)
        XCTAssertNotNil(box.contexts[0].tailscale)
        XCTAssertNil(box.contexts[1].tailscale)
    }
}
