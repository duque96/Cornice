import Foundation
import CorniceKit

/// Ships widgets inside the app bundle and installs them on first run.
public enum WidgetInstaller {
    /// Installs missing bundles and replaces installed ones when the bundled
    /// version is newer. Same-version folders are left alone: user edits win.
    @discardableResult
    public static func installBundledWidgets(from source: URL, into destination: URL) -> [WidgetID] {
        WidgetBundleStore.ensureDirectoryExists(destination)

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )) ?? []

        var installed: [WidgetID] = []

        for bundle in contents where bundle.pathExtension == WidgetBundleStore.bundleExtension {
            let target = destination.appendingPathComponent(bundle.lastPathComponent)
            let incoming = try? WidgetBundleStore.load(bundleAt: bundle)

            if FileManager.default.fileExists(atPath: target.path) {
                let installedCopy = try? WidgetBundleStore.load(bundleAt: target)
                let shouldUpgrade: Bool

                if let installedCopy, let incoming {
                    shouldUpgrade = incoming.manifest.version > installedCopy.manifest.version
                } else {
                    // Corrupt or unreadable: replace it with the known-good copy.
                    shouldUpgrade = true
                }

                guard shouldUpgrade else { continue }
                try? FileManager.default.removeItem(at: target)
            }

            do {
                try FileManager.default.copyItem(at: bundle, to: target)
                if let widget = try? WidgetBundleStore.load(bundleAt: target) {
                    installed.append(widget.manifest.id)
                }
            } catch {
                FileHandle.standardError.write(
                    Data("[widgets] could not install \(bundle.lastPathComponent): \(error)\n".utf8)
                )
            }
        }

        return installed
    }

    /// Where the app bundle keeps its widgets.
    public static var bundledWidgetsURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Widgets", isDirectory: true)
    }
}
