import XCTest
import SwiftUI
@testable import CorniceCore

/// Renders the surface offscreen so layout regressions can be inspected as images.
/// Files land in `$CORNICE_SNAPSHOT_DIR` (defaults to the temporary directory).
@MainActor
final class SurfaceSnapshotTests: XCTestCase {
    private var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CORNICE_SNAPSHOT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    func testRenderOpenSurface() throws {
        let model = NotchSurfaceModel(
            notchSize: CGSize(width: 185, height: 33),
            expandedSize: CGSize(width: 420, height: 190),
            notchCornerRadius: 10,
            mode: .hardware
        )
        model.state = .open

        try render(model, name: "cornice-open")
    }

    func testRenderTransitionFilmstrip() throws {
        let model = NotchSurfaceModel(
            notchSize: CGSize(width: 185, height: 33),
            expandedSize: CGSize(width: 420, height: 190),
            notchCornerRadius: 10,
            mode: .hardware
        )
        model.state = .open

        for step in stride(from: 0.0, through: 1.0, by: 0.25) {
            let view = NotchSurfaceView(model: model, previewProgress: step)
                .frame(width: model.expandedSize.width, height: model.expandedSize.height)
                .background(Color(white: 0.62))

            try write(view, name: String(format: "cornice-step-%.2f", step))
        }
    }

    func testRenderCollapsedSurface() throws {
        let model = NotchSurfaceModel(
            notchSize: CGSize(width: 185, height: 33),
            expandedSize: CGSize(width: 420, height: 190),
            notchCornerRadius: 10,
            mode: .hardware
        )

        try render(model, name: "cornice-collapsed")
    }

    private func render(_ model: NotchSurfaceModel, name: String) throws {
        let view = NotchSurfaceView(model: model)
            .frame(width: model.expandedSize.width, height: model.expandedSize.height)
            .background(Color(white: 0.62))

        try write(view, name: name)
    }

    private func write(_ view: some View, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not render \(name)")
            return
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
