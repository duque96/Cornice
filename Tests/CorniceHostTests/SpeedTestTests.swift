import SwiftUI
import XCTest
@testable import CorniceHost
@testable import CorniceCore
@testable import CorniceKit

// MARK: - Helpers

private func shellScript(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("fake-networkquality-\(UUID().uuidString).sh")
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o755)],
        ofItemAtPath: url.path
    )
    return url
}

private let downloadJSON = """
{"base_rtt": 19.5, "dl_throughput": 625000000, "dl_responsiveness": 1441.4,
 "interface_name": "en0", "test_endpoint": "speed.example.com"}
"""

private let uploadJSON = """
{"base_rtt": 19.5, "ul_throughput": 412000000, "ul_responsiveness": 900,
 "interface_name": "en0", "test_endpoint": "speed.example.com"}
"""

private func twoPhaseScript(argsURL: URL) -> String {
    """
    printf '%s\\n' "$*" >> '\(argsURL.path)'
    if [ "$1" = "-u" ]; then
      printf '%s\\n' '\(downloadJSON)'
    else
      printf '%s\\n' '\(uploadJSON)'
    fi
    """
}

/// Waits for the fake tool to actually start, so a cancel cannot race the spawn.
private func waitForFile(_ url: URL, timeout: TimeInterval = 3) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return false
}

// MARK: - Parser

final class SpeedTestParsingTests: XCTestCase {
    func testParsesDownloadReport() throws {
        let measurement = try XCTUnwrap(
            SystemSpeedTest.parse(Data(downloadJSON.utf8), phase: .download)
        )

        XCTAssertEqual(measurement.phase, .download)
        XCTAssertEqual(measurement.bitsPerSecond, 625_000_000)
        XCTAssertEqual(measurement.megabitsPerSecond, 625)
        XCTAssertEqual(measurement.latencyMilliseconds, 19.5)
        XCTAssertEqual(measurement.responsiveness, 1441.4)
        XCTAssertEqual(measurement.interfaceName, "en0")
        XCTAssertEqual(measurement.endpoint, "speed.example.com")
    }

    func testParsesUploadReport() throws {
        let measurement = try XCTUnwrap(
            SystemSpeedTest.parse(Data(uploadJSON.utf8), phase: .upload)
        )

        XCTAssertEqual(measurement.phase, .upload)
        XCTAssertEqual(measurement.megabitsPerSecond, 412)
        XCTAssertEqual(measurement.responsiveness, 900)
    }

    func testAcceptsNewerCapacityKeys() throws {
        // Recent builds may report Mbps under different names.
        let json = """
        {"base_rtt": 12, "downlink_capacity_mbps": 940.5, "downlink_responsiveness_rpm": 1200}
        """

        let measurement = try XCTUnwrap(
            SystemSpeedTest.parse(Data(json.utf8), phase: .download)
        )

        XCTAssertEqual(measurement.megabitsPerSecond, 940.5)
        XCTAssertEqual(measurement.responsiveness, 1200)
    }

    func testRejectsGarbage() {
        XCTAssertNil(SystemSpeedTest.parse(Data("not json".utf8), phase: .download))
        XCTAssertNil(SystemSpeedTest.parse(Data("{}".utf8), phase: .download))
        // Upload JSON used for a download measurement has no download figure.
        XCTAssertNil(SystemSpeedTest.parse(Data(uploadJSON.utf8), phase: .download))
    }

    func testNonPositiveThroughputIsRejected() {
        let json = #"{"dl_throughput": 0}"#
        XCTAssertNil(SystemSpeedTest.parse(Data(json.utf8), phase: .download))
    }
}

// MARK: - Runner

final class SpeedTestRunnerTests: XCTestCase {
    func testRunsBothPhasesInOrderWithClampedDuration() async throws {
        let argsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("args-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: argsURL) }

        let script = try shellScript(twoPhaseScript(argsURL: argsURL))
        defer { try? FileManager.default.removeItem(at: script) }

        // 120 s must be clamped to the host maximum of 30 s.
        let result = await SystemSpeedTest(binary: script, resultsURL: nil)
            .run(duration: 120)

        guard case .success(let report) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(report.download?.megabitsPerSecond, 625)
        XCTAssertEqual(report.upload?.megabitsPerSecond, 412)

        let calls = try String(contentsOf: argsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(calls, ["-u -M 30 -c", "-d -M 30 -c"])
    }

    func testSecondRunWhileBusyIsRejected() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("started-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }

        let script = try shellScript("touch '\(marker.path)'\nsleep 3\nprintf '%s\\n' '\(downloadJSON)'")
        defer { try? FileManager.default.removeItem(at: script) }

        let service = SystemSpeedTest(binary: script, resultsURL: nil)
        let first = Task { await service.run(duration: 5) }

        let started = await waitForFile(marker)
        XCTAssertTrue(started, "the fake tool never started")

        let second = await service.run(duration: 5)
        guard case .failure(.busy) = second else {
            await service.cancel()
            _ = await first.value
            return XCTFail("expected busy, got \(second)")
        }

        await service.cancel()
        _ = await first.value
    }

    func testCancelStopsTheRun() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("started-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }

        let script = try shellScript("touch '\(marker.path)'\nsleep 10\nprintf '%s\\n' '\(downloadJSON)'")
        defer { try? FileManager.default.removeItem(at: script) }

        let service = SystemSpeedTest(binary: script, resultsURL: nil)
        let run = Task { await service.run(duration: 10) }

        let started = await waitForFile(marker)
        XCTAssertTrue(started, "the fake tool never started")

        let cancelStarted = Date()
        await service.cancel()
        let result = await run.value

        guard case .failure(.cancelled) = result else {
            return XCTFail("expected cancelled, got \(result)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelStarted), 4)
    }

    func testUnparsableOutputIsACommandFailure() async throws {
        let script = try shellScript("printf '%s\\n' 'no me gusta este JSON'")
        defer { try? FileManager.default.removeItem(at: script) }

        let result = await SystemSpeedTest(binary: script, resultsURL: nil).run(duration: 5)

        guard case .failure(.commandFailed(let message)) = result else {
            return XCTFail("expected commandFailed, got \(result)")
        }
        XCTAssertTrue(message.contains("JSON"))
    }

    func testMissingBinaryIsUnavailable() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-networkquality-\(UUID().uuidString)")

        let result = await SystemSpeedTest(binary: missing, resultsURL: nil).run(duration: 5)

        guard case .failure(.unavailable) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
    }
}

// MARK: - Persistence

final class SpeedTestPersistenceTests: XCTestCase {
    func testStoresAndReloadsTheLastReport() async throws {
        let argsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("args-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: argsURL) }

        let script = try shellScript(twoPhaseScript(argsURL: argsURL))
        defer { try? FileManager.default.removeItem(at: script) }

        let resultsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speedtest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("speedtest.json")
        defer { try? FileManager.default.removeItem(at: resultsURL.deletingLastPathComponent()) }

        let service = SystemSpeedTest(binary: script, resultsURL: resultsURL)
        let result = await service.run(duration: 5)
        guard case .success(let report) = result else {
            return XCTFail("expected success, got \(result)")
        }

        // A fresh instance represents the app after a restart.
        let reloaded = await SystemSpeedTest(binary: script, resultsURL: resultsURL).last()

        XCTAssertEqual(reloaded?.download?.bitsPerSecond, report.download?.bitsPerSecond)
        XCTAssertEqual(reloaded?.upload?.bitsPerSecond, report.upload?.bitsPerSecond)
        XCTAssertEqual(reloaded?.upload?.endpoint, "speed.example.com")
    }

    func testMissingFileMeansNoPreviousReport() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nothing-\(UUID().uuidString).json")

        let report = await SystemSpeedTest(binary: nil, resultsURL: missing).last()
        XCTAssertNil(report)
    }
}

// MARK: - Capability wiring

private struct FakeSpeedTest: SpeedTestControlling {
    func run(
        duration: TimeInterval,
        progress: (@Sendable (SpeedTestProgress) -> Void)?
    ) async -> Result<SpeedTestReport, SpeedTestError> {
        .failure(.unavailable)
    }

    func last() async -> SpeedTestReport? { nil }
}

@MainActor
private final class SpeedProbe: CorniceWidget {
    func makeView() -> AnyView { AnyView(EmptyView()) }
    func activate() {}
    func deactivate() {}
    func tick(_ now: Date) {}
}

@MainActor
private final class SpeedProbeBox {
    var contexts: [WidgetContext] = []
}

@MainActor
private struct SpeedProbeFactory: WidgetFactory {
    let manifest: WidgetManifest
    let box: SpeedProbeBox

    func make(context: WidgetContext) -> any CorniceWidget {
        box.contexts.append(context)
        return SpeedProbe()
    }
}

final class SpeedTestCapabilityTests: XCTestCase {
    @MainActor
    func testCapabilityGatesTheController() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-speed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let box = SpeedProbeBox()

        let withCapability = SpeedProbeFactory(
            manifest: WidgetManifest(
                id: "com.example.with-speedtest",
                name: "With",
                version: SemanticVersion(1, 0, 0),
                capabilities: [.speedtest],
                placement: Placement(size: GridSize(columns: 1, rows: 1))
            ),
            box: box
        )

        let without = SpeedProbeFactory(
            manifest: WidgetManifest(
                id: "com.example.without-speedtest",
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
            speedtest: FakeSpeedTest()
        )
        host.start()

        XCTAssertEqual(box.contexts.count, 2)
        XCTAssertNotNil(box.contexts[0].speedtest)
        XCTAssertNil(box.contexts[1].speedtest)
    }
}
