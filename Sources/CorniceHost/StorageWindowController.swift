import AppKit
import SwiftUI
import CorniceCore
import CorniceKit

@MainActor
public final class StorageWindowController: NSWindowController {
    private let storage: SystemStorage

    public init(storage: SystemStorage) {
        self.storage = storage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 520)
        window.center()
        window.setFrameAutosaveName("CorniceStorage")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(language: AppLanguage) {
        guard let window else { return }

        window.title = Translator(language)("Storage", "Almacenamiento")
        let model = StorageReviewModel(storage: storage, language: language)
        window.contentViewController = NSHostingController(
            rootView: StorageReviewView(model: model) { [weak self] in
                self?.close()
            }
        )

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Compact Options section that points at the full review window.
public struct StorageSettingsView: View {
    private let storage: SystemStorage
    private let language: AppLanguage
    private let onReview: () -> Void

    @State private var status: StorageStatus?

    public init(storage: SystemStorage, language: AppLanguage, onReview: @escaping () -> Void) {
        self.storage = storage
        self.language = language
        self.onReview = onReview
    }

    public var body: some View {
        let t = Translator(language)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Storage", "Almacenamiento"))
                    .font(.system(size: 17, weight: .semibold))
                Text(t(
                    "Review caches, logs and build products before deleting anything.",
                    "Revisa cachés, registros y productos de compilación antes de borrar nada."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let status {
                    Text("\(StorageFormat.bytes(status.freeBytes)) \(t("free of", "libres de")) \(StorageFormat.bytes(status.totalBytes))")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(StorageFormat.bytes(status.recoverableBytes)) \(t("reclaimable with the recommended cleanup.", "recuperables con la limpieza recomendada."))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(t("Reading…", "Leyendo…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Button(t("Review storage…", "Revisar almacenamiento…"), action: onReview)
                    .controlSize(.small)
            }
        }
        .task {
            status = await storage.status()
        }
    }
}
