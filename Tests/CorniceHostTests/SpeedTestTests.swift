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

/// A fake tool that mimics `networkQuality` closely enough: progress lines on
/// stdout (a TTY at runtime) and the JSON report on the `-c` path.
private func twoPhaseScript(argsURL: URL) -> String {
    """
    printf '%s\\n' "$*" >> '\(argsURL.path)'
    json=''
    for arg in "$@"; do
      case "$arg" in
        -c*) json="${arg#-c}" ;;
      esac
    done
    if [ "$1" = "-u" ]; then
      printf 'Downlink: capacity 120.500 Mbps, responsiveness 0 RPM (3.094 MB, 1 flow) - Uplink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows)\\n'
      printf 'Downlink: capacity 300.000 Mbps, responsiveness 900 RPM (12.859 MB, 2 flows) - Uplink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows)\\n'
      printf '%s\\n' '\(downloadJSON)' > "$json"
    else
      printf 'Downlink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows) - Uplink: capacity 240.250 Mbps, responsiveness 700 RPM (8.000 MB, 1 flow)\\n'
      printf '%s\\n' '\(uploadJSON)' > "$json"
    fi
    """
}

private func hangingScript(marker: URL?, json: String, seconds: Int) -> String {
    """
    \(marker.map { "touch '\($0.path)'" } ?? "")
    sleep \(seconds)
    json=''
    for arg in "$@"; do
      case "$arg" in
        -c*) json="${arg#-c}" ;;
      esac
    done
    printf '%s\\n' '\(json)' > "$json"
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

/// The progress callback is `@Sendable`; this keeps the received order.
private final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SpeedTestProgress] = []

    func add(_ event: SpeedTestProgress) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var samples: [(phase: SpeedTestPhase, bitsPerSecond: Double, responsiveness: Double?)] {
        lock.lock()
        defer { lock.unlock() }
        return events.compactMap {
            guard case .sample(let phase, let bitsPerSecond, let responsiveness) = $0 else {
                return nil
            }
            return (phase, bitsPerSecond, responsiveness)
        }
    }
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

    // MARK: Live progress lines

    func testParsesDownloadProgressLine() throws {
        let line = "\u{1B}[2K\rDownlink: capacity 324.260 Mbps, responsiveness 1050 RPM (71.058 MB, 2 flows) - Uplink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows)"

        let sample = try XCTUnwrap(SystemSpeedTest.parseProgressLine(line, phase: .download))

        XCTAssertEqual(sample.bitsPerSecond, 324_260_000, accuracy: 1)
        XCTAssertEqual(sample.responsiveness, 1050)
    }

    func testUploadLineUsesItsOwnSection() throws {
        // The downlink half reports 0 RPM; the upload half is the one we want.
        let line = "Downlink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows) - Uplink: capacity 92.204 Mbps, responsiveness 907 RPM (42.062 MB, 4 flows)"

        let sample = try XCTUnwrap(SystemSpeedTest.parseProgressLine(line, phase: .upload))

        XCTAssertEqual(sample.bitsPerSecond, 92_204_000, accuracy: 1)
        XCTAssertEqual(sample.responsiveness, 907)
    }

    func testProgressLineWithoutTrafficIsIgnored() {
        let line = "Downlink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows) - Uplink: capacity 0.000 Mbps, responsiveness 0 RPM (0 B, 0 flows)"

        XCTAssertNil(SystemSpeedTest.parseProgressLine(line, phase: .download))
        XCTAssertNil(SystemSpeedTest.parseProgressLine(line, phase: .upload))
        XCTAssertNil(SystemSpeedTest.parseProgressLine("not a progress line", phase: .download))
    }

    func testProgressLineAcceptsCommaDecimal() throws {
        let line = "Downlink: capacity 120,500 Mbps, responsiveness 0 RPM - Uplink: capacity 0,000 Mbps, responsiveness 0 RPM"

        let sample = try XCTUnwrap(SystemSpeedTest.parseProgressLine(line, phase: .download))

        XCTAssertEqual(sample.bitsPerSecond, 120_500_000, accuracy: 1)
        XCTAssertNil(sample.responsiveness)
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
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[0].hasPrefix("-u -M 30 -v -c"), calls[0])
        XCTAssertTrue(calls[0].hasSuffix(".json"), calls[0])
        XCTAssertTrue(calls[1].hasPrefix("-d -M 30 -v -c"), calls[1])
    }

    func testStreamsLiveSamplesBeforeTheFinalReport() async throws {
        let argsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("args-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: argsURL) }

        let script = try shellScript(twoPhaseScript(argsURL: argsURL))
        defer { try? FileManager.default.removeItem(at: script) }

        let box = SampleBox()
        let result = await SystemSpeedTest(binary: script, resultsURL: nil)
            .run(duration: 5) { box.add($0) }

        guard case .success = result else {
            return XCTFail("expected success, got \(result)")
        }

        let samples = box.samples
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0].phase, .download)
        XCTAssertEqual(samples[0].bitsPerSecond, 120_500_000, accuracy: 1)
        XCTAssertNil(samples[0].responsiveness)
        XCTAssertEqual(samples[1].phase, .download)
        XCTAssertEqual(samples[1].bitsPerSecond, 300_000_000, accuracy: 1)
        XCTAssertEqual(samples[1].responsiveness, 900)
        XCTAssertEqual(samples[2].phase, .upload)
        XCTAssertEqual(samples[2].bitsPerSecond, 240_250_000, accuracy: 1)
        XCTAssertEqual(samples[2].responsiveness, 700)
    }

    func testSecondRunWhileBusyIsRejected() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("started-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }

        let script = try shellScript(
            hangingScript(marker: marker, json: downloadJSON, seconds: 3)
        )
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

        let script = try shellScript(
            hangingScript(marker: marker, json: downloadJSON, seconds: 10)
        )
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

    func testMissingJsonIsACommandFailure() async throws {
        // Exit 0 with no report file: the tool lied about succeeding.
        let script = try shellScript("printf 'Downlink: capacity 10.000 Mbps, responsiveness 0 RPM\\n'")
        defer { try? FileManager.default.removeItem(at: script) }

        let result = await SystemSpeedTest(binary: script, resultsURL: nil).run(duration: 5)

        guard case .failure(.commandFailed(let message)) = result else {
            return XCTFail("expected commandFailed, got \(result)")
        }
        XCTAssertTrue(message.contains("networkQuality"))
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
