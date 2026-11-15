import Foundation

/// One fixed, allow-listed place the cleaner can empty. Roots are hardcoded:
/// nothing here comes from a widget or the UI.
struct StorageCategory: Identifiable, Sendable {
    enum Group: Sendable {
        case recommended
        case advanced
    }

    enum Risk: Sendable {
        case safe
        case caution
        case userData
    }

    enum Filter: Sendable {
        case all
        case prefixes([String])
        case notPrefixes([String])

        func includes(_ name: String) -> Bool {
            switch self {
            case .all:
                return true
            case .prefixes(let prefixes):
                return prefixes.contains { name.hasPrefix($0) }
            case .notPrefixes(let prefixes):
                return !prefixes.contains { name.hasPrefix($0) }
            }
        }
    }

    let id: String
    let group: Group
    let risk: Risk
    let titleEN: String
    let titleES: String
    let noteEN: String?
    let noteES: String?
    let roots: [URL]
    let filter: Filter
    let defaultSelected: Bool
}

struct StorageItem: Identifiable, Sendable, Equatable {
    let url: URL
    let name: String
    let bytes: Int64
    let modified: Date?

    var id: String { url.path }
}

struct StorageCategorySize: Sendable {
    let id: String
    let bytes: Int64
    let items: [StorageItem]
}

struct StorageCleanResult: Sendable {
    var removedBytes: Int64
    var removedItems: Int
    var failures: [String]

    static let empty = StorageCleanResult(removedBytes: 0, removedItems: 0, failures: [])

    mutating func merge(_ other: StorageCleanResult) {
        removedBytes += other.removedBytes
        removedItems += other.removedItems
        failures.append(contentsOf: other.failures)
    }
}

enum StorageCatalog {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    /// Every category shown in the review window. Recommended ones are safe and
    /// preselected; advanced ones need an explicit opt-in.
    static var cleanable: [StorageCategory] {
        [
            appCaches,
            appleCaches,
            logs,
            derivedData,
            deviceSupport,
            simulatorCaches,
            devCaches,
            containerCaches,
            trash,
            iphoneBackups,
        ]
    }

    static var appCaches: StorageCategory {
        StorageCategory(
            id: "appCaches",
            group: .recommended,
            risk: .safe,
            titleEN: "App caches",
            titleES: "Cachés de apps",
            noteEN: "Third-party caches. Apps rebuild them.",
            noteES: "Cachés de terceros. Las apps las regeneran.",
            roots: [home.appendingPathComponent("Library/Caches")],
            filter: .notPrefixes(["com.apple."]),
            defaultSelected: true
        )
    }

    static var appleCaches: StorageCategory {
        StorageCategory(
            id: "appleCaches",
            group: .advanced,
            risk: .caution,
            titleEN: "Apple caches",
            titleES: "Cachés de Apple",
            noteEN: "User-level Apple caches. macOS rebuilds them.",
            noteES: "Cachés de Apple a nivel de usuario. macOS las regenera.",
            roots: [home.appendingPathComponent("Library/Caches")],
            filter: .prefixes(["com.apple."]),
            defaultSelected: false
        )
    }

    static var logs: StorageCategory {
        StorageCategory(
            id: "logs",
            group: .recommended,
            risk: .safe,
            titleEN: "Logs",
            titleES: "Registros",
            noteEN: "Diagnostic logs.",
            noteES: "Registros de diagnóstico.",
            roots: [home.appendingPathComponent("Library/Logs")],
            filter: .all,
            defaultSelected: true
        )
    }

    static var derivedData: StorageCategory {
        StorageCategory(
            id: "derivedData",
            group: .recommended,
            risk: .safe,
            titleEN: "Xcode DerivedData",
            titleES: "Xcode DerivedData",
            noteEN: "Build products; Xcode rebuilds them.",
            noteES: "Productos de compilación; Xcode los regenera.",
            roots: [home.appendingPathComponent("Library/Developer/Xcode/DerivedData")],
            filter: .all,
            defaultSelected: true
        )
    }

    static var deviceSupport: StorageCategory {
        StorageCategory(
            id: "deviceSupport",
            group: .advanced,
            risk: .caution,
            titleEN: "Xcode iOS DeviceSupport",
            titleES: "Xcode iOS DeviceSupport",
            noteEN: "Xcode re-downloads it on the next debug session.",
            noteES: "Xcode lo vuelve a descargar en la próxima depuración.",
            roots: [home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")],
            filter: .all,
            defaultSelected: false
        )
    }

    static var simulatorCaches: StorageCategory {
        StorageCategory(
            id: "simulatorCaches",
            group: .advanced,
            risk: .safe,
            titleEN: "Simulator caches",
            titleES: "Cachés de simuladores",
            noteEN: "CoreSimulator runtime caches.",
            noteES: "Cachés de ejecución de CoreSimulator.",
            roots: [home.appendingPathComponent("Library/Developer/CoreSimulator/Caches")],
            filter: .all,
            defaultSelected: false
        )
    }

    static var devCaches: StorageCategory {
        StorageCategory(
            id: "devCaches",
            group: .advanced,
            risk: .caution,
            titleEN: "Development caches",
            titleES: "Cachés de desarrollo",
            noteEN: "npm, Cargo, Gradle and Maven caches. They download again when needed.",
            noteES: "Cachés de npm, Cargo, Gradle y Maven. Se descargan otra vez cuando hacen falta.",
            roots: [
                home.appendingPathComponent(".npm/_cacache"),
                home.appendingPathComponent(".cargo/registry"),
                home.appendingPathComponent(".gradle/caches"),
                home.appendingPathComponent(".m2/repository"),
            ],
            filter: .all,
            defaultSelected: false
        )
    }

    static var containerCaches: StorageCategory {
        StorageCategory(
            id: "containerCaches",
            group: .advanced,
            risk: .caution,
            titleEN: "Sandboxed app caches",
            titleES: "Cachés de apps sandbox",
            noteEN: "Caches inside app containers. Close those apps first.",
            noteES: "Cachés dentro de contenedores de apps. Cierra esas apps antes.",
            roots: containerCacheRoots(),
            filter: .all,
            defaultSelected: false
        )
    }

    static var trash: StorageCategory {
        StorageCategory(
            id: "trash",
            group: .advanced,
            risk: .userData,
            titleEN: "Trash",
            titleES: "Papelera",
            noteEN: "Empties the Trash permanently.",
            noteES: "Vacía la Papelera definitivamente.",
            roots: [home.appendingPathComponent(".Trash")],
            filter: .all,
            defaultSelected: false
        )
    }

    static var iphoneBackups: StorageCategory {
        StorageCategory(
            id: "iphoneBackups",
            group: .advanced,
            risk: .userData,
            titleEN: "iPhone backups",
            titleES: "Copias de iPhone",
            noteEN: "Local iOS device backups. They cannot be recovered from here.",
            noteES: "Copias locales de dispositivos iOS. No se pueden recuperar desde aquí.",
            roots: [home.appendingPathComponent("Library/Application Support/MobileSync/Backup")],
            filter: .all,
            defaultSelected: false
        )
    }

    /// Every `Caches` directory owned by a sandboxed app, for both regular
    /// containers and group containers.
    static func containerCacheRoots() -> [URL] {
        let fileManager = FileManager.default
        let bases = [
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers"),
        ]

        var roots: [URL] = []
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        let homePath = home.path + "/"

        for base in bases {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                if (try? entry.resourceValues(forKeys: keys))?.isSymbolicLink == true {
                    continue
                }

                let caches = base.lastPathComponent == "Containers"
                    ? entry.appendingPathComponent("Data/Library/Caches")
                    : entry.appendingPathComponent("Library/Caches")

                if (try? caches.resourceValues(forKeys: keys))?.isSymbolicLink == true {
                    continue
                }
                let resolved = caches.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(homePath) else { continue }
                if fileManager.fileExists(atPath: caches.path) {
                    roots.append(caches)
                }
            }
        }
        return roots
    }
}
