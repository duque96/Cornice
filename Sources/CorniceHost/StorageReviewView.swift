import AppKit
import SwiftUI
import CorniceCore
import CorniceKit

enum StorageFormat {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.isAdaptive = true
        formatter.includesUnit = true
        return formatter.string(fromByteCount: value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

@MainActor
@Observable
final class StorageReviewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case recommended
        case advanced
        case analyze

        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let category: StorageCategory
        var bytes: Int64
        var items: [StorageItem]
        var selected: Bool

        var id: String { category.id }
    }

    let storage: SystemStorage
    let language: AppLanguage

    var status: StorageStatus?
    var rows: [Row] = []
    var tab: Tab = .recommended
    var isLoading = true
    var isAdvancedLoading = false
    var isCleaning = false
    var analysisLoading = false
    var analysisLoaded = false
    var largeFiles: [StorageItem] = []
    var oldDownloads: [StorageItem] = []
    var snapshotCount: Int?
    private var advancedGeneration = 0
    var message: String?
    var failures: [String] = []

    init(storage: SystemStorage, language: AppLanguage) {
        self.storage = storage
        self.language = language
    }

    var recommendedRows: [Row] {
        rows.filter { $0.category.group == .recommended }
    }

    var advancedRows: [Row] {
        rows.filter { $0.category.group == .advanced }
    }

    var selectedBytes: Int64 {
        rows.reduce(Int64(0)) { $0 + ($1.selected ? $1.bytes : 0) }
    }

    var selectedIDs: Set<String> {
        Set(rows.filter(\.selected).map(\.id))
    }

    var hasUserDataSelected: Bool {
        rows.contains { $0.selected && $0.category.risk == .userData }
    }

    func title(_ row: Row) -> String {
        language.resolved == .es ? row.category.titleES : row.category.titleEN
    }

    func note(_ row: Row) -> String? {
        language.resolved == .es ? row.category.noteES : row.category.noteEN
    }

    func setSelected(_ id: String, _ selected: Bool) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].selected = selected
    }

    func load() async {
        isLoading = true
        failures = []
        message = nil

        if let quick = await storage.capacity() {
            status = quick
        }
        status = await storage.status()

        let recommended = await storage.scanRecommended(force: true)
        rows = makeRows(recommended)
        isLoading = false

        advancedGeneration += 1
        let generation = advancedGeneration
        isAdvancedLoading = true
        Task { await loadAdvanced(generation: generation) }
    }

    private func makeRows(_ sizes: [StorageCategorySize]) -> [Row] {
        StorageCatalog.cleanable.compactMap { category in
            guard let size = sizes.first(where: { $0.id == category.id }) else { return nil }
            return Row(
                category: category,
                bytes: size.bytes,
                items: size.items,
                selected: category.defaultSelected && size.bytes > 0
            )
        }
    }

    private func loadAdvanced(generation: Int) async {
        let advanced = await storage.scanAdvanced(force: true)
        guard generation == advancedGeneration else { return }

        let existing = Set(rows.map(\.id))
        rows.append(contentsOf: makeRows(advanced).filter { !existing.contains($0.id) })

        isAdvancedLoading = false
    }

    func loadAnalysis() async {
        guard !analysisLoaded, !analysisLoading else { return }
        analysisLoading = true
        largeFiles = await storage.largeFiles()
        oldDownloads = await storage.oldDownloads()
        snapshotCount = await storage.localSnapshotCount()
        analysisLoaded = true
        analysisLoading = false
    }

    func clean() async {
        guard !isCleaning else { return }
        isCleaning = true
        message = nil
        failures = []

        let result = await storage.clean(ids: selectedIDs)
        let freed = result.removedBytes
        await load()

        failures = result.failures
        if freed > 0 {
            message = String(
                format: language.resolved == .es ? "Liberados %@" : "Freed %@",
                StorageFormat.bytes(freed)
            )
        } else {
            message = language.resolved == .es ? "No había nada que borrar." : "Nothing to delete."
        }

        isCleaning = false
    }

    func trash(_ item: StorageItem) async {
        if let error = await storage.trash(item.url) {
            failures.append("\(item.name): \(error)")
            return
        }

        largeFiles.removeAll { $0.id == item.id }
        oldDownloads.removeAll { $0.id == item.id }
        message = language.resolved == .es ? "Movido a la Papelera." : "Moved to Trash."
    }
}

struct StorageReviewView: View {
    @State private var model: StorageReviewModel
    @State private var confirmClean = false
    @State private var trashTarget: StorageItem?

    private let onClose: () -> Void

    init(model: StorageReviewModel, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onClose = onClose
    }

    var body: some View {
        let t = Translator(model.language)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Storage", "Almacenamiento"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(t(
                        "Review what will be deleted. Nothing is removed until you confirm.",
                        "Revisa lo que se va a borrar. Nada se elimina hasta que confirmes."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let status = model.status {
                capacity(status, t)
            }

            Picker("", selection: $model.tab) {
                Text(t("Recommended", "Recomendado")).tag(StorageReviewModel.Tab.recommended)
                Text(t("Advanced", "Avanzado")).tag(StorageReviewModel.Tab.advanced)
                Text(t("Analyze", "Analizar")).tag(StorageReviewModel.Tab.analyze)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch model.tab {
                    case .recommended:
                        categoryList(model.recommendedRows, t)
                    case .advanced:
                        if model.isAdvancedLoading && model.advancedRows.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(t("Scanning…", "Analizando…"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            categoryList(model.advancedRows, t)
                        }
                    case .analyze:
                        analysis(t)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer(t)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 600)
        .task { await model.load() }
        .alert(t("Delete selected items?", "¿Borrar lo seleccionado?"), isPresented: $confirmClean) {
            Button(t("Cancel", "Cancelar"), role: .cancel) {}
            Button(t("Delete", "Borrar"), role: .destructive) {
                Task { await model.clean() }
            }
        } message: {
            Text(model.hasUserDataSelected
                ? t(
                    "This includes personal data (Trash or device backups) and cannot be undone.",
                    "Esto incluye datos personales (Papelera o copias de dispositivos) y no se puede deshacer."
                )
                : t(
                    "Selected caches will be deleted. Apps rebuild them when needed.",
                    "Se borrarán las cachés seleccionadas. Las apps las regeneran cuando hacen falta."
                ))
        }
        .confirmationDialog(
            t("Move to Trash?", "¿Mover a la Papelera?"),
            isPresented: Binding(
                get: { trashTarget != nil },
                set: { if !$0 { trashTarget = nil } }
            ),
            presenting: trashTarget
        ) { item in
            Button(t("Move to Trash", "Mover a la Papelera"), role: .destructive) {
                Task { await model.trash(item) }
            }
        } message: { item in
            Text(item.name)
        }
    }

    private func capacity(_ status: StorageStatus, _ t: Translator) -> some View {
        let freeFraction = Double(status.freeBytes) / Double(max(1, status.totalBytes))
        let usedFraction = min(1, max(0, 1 - freeFraction))
        let color: Color = freeFraction < 0.10 ? .red : (freeFraction < 0.20 ? .orange : .green)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(StorageFormat.bytes(status.freeBytes)) \(t("free", "libres"))")
                    .font(.system(size: 12, weight: .medium))
                Text(t("of", "de") + " \(StorageFormat.bytes(status.totalBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(StorageFormat.percent(freeFraction)) \(t("free", "libre"))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, proxy.size.width * usedFraction))
                }
            }
            .frame(height: 4)
        }
    }

    private func categoryList(_ rows: [StorageReviewModel.Row], _ t: Translator) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    categoryRow(row, t)
                    Divider()
                        .opacity(0.4)
                }
            }
        }
    }

    private func categoryRow(_ row: StorageReviewModel.Row, _ t: Translator) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.rows.first(where: { $0.id == row.id })?.selected ?? false },
                set: { model.setSelected(row.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(row.bytes == 0 || model.isLoading || model.isCleaning)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.title(row))
                        .font(.system(size: 12, weight: .medium))

                    if row.category.risk == .userData {
                        Text(t("personal", "personal"))
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.16), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Text(StorageFormat.bytes(row.bytes))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let note = model.note(row) {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !row.items.isEmpty {
                    Text(row.items.prefix(3).map {
                        "\($0.name) \(StorageFormat.bytes($0.bytes))"
                    }.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func analysis(_ t: Translator) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.analysisLoaded {
                    if model.analysisLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(t("Analyzing large files…", "Analizando archivos grandes…"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(t(
                            "Analyze large files and old downloads",
                            "Analizar archivos grandes y descargas antiguas"
                        )) {
                            Task { await model.loadAnalysis() }
                        }
                        .controlSize(.small)
                    }
                } else {
                    fileSection(
                        t("Large files (over 1 GB)", "Archivos grandes (más de 1 GB)"),
                        items: model.largeFiles,
                        empty: t("No large files found.", "No hay archivos grandes."),
                        t
                    )

                    fileSection(
                        t("Old downloads (90+ days)", "Descargas antiguas (90+ días)"),
                        items: model.oldDownloads,
                        empty: t("No old downloads found.", "No hay descargas antiguas."),
                        t
                    )

                    if let count = model.snapshotCount, count > 0 {
                        Text(t(
                            "\(count) local Time Machine snapshots. Deleting them requires an administrator.",
                            "\(count) snapshots locales de Time Machine. Borrarlos requiere administrador."
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    Text(t(
                        "System caches in /Library/Caches require an administrator; Cornice does not touch them.",
                        "Las cachés de sistema en /Library/Caches requieren administrador; Cornice no las toca."
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func fileSection(
        _ title: String,
        items: [StorageItem],
        empty: String,
        _ t: Translator
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(StorageFormat.bytes(item.bytes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button(t("Show", "Mostrar")) {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        .controlSize(.mini)

                        Button(t("Trash", "Papelera")) {
                            trashTarget = item
                        }
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    private func footer(_ t: Translator) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(StorageFormat.bytes(model.selectedBytes)) \(t("selected", "seleccionados"))")
                    .font(.system(size: 11, weight: .medium))

                if model.hasUserDataSelected {
                    Text(t("Includes personal data", "Incluye datos personales"))
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }

                if let message = model.message {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let failure = model.failures.first {
                    Text(failure)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(t("Close", "Cerrar"), action: onClose)

            if model.isCleaning {
                ProgressView()
                    .controlSize(.small)
            }

            Button(String(
                format: t("Free %@", "Liberar %@"),
                StorageFormat.bytes(model.selectedBytes)
            )) {
                confirmClean = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selectedBytes == 0 || model.isLoading || model.isCleaning)
        }
    }
}
