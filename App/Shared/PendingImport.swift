import Foundation

/// A capture handed from the Share Extension to the app.
///
/// Extensions can't open the host app, so the extension drops one of these
/// into the App Group container and the app drains the folder the next time
/// it becomes active. Images are written alongside as files and referenced
/// by name to keep the JSON small.
struct PendingImport: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case url, text, images
    }

    var id: UUID = UUID()
    var kind: Kind
    var url: URL?
    var text: String?
    var imageFileNames: [String] = []
    var createdAt: Date = Date()
}

/// Reads and writes `PendingImport`s in the shared container. Used by both
/// targets; the extension only writes, the app only reads and removes.
struct PendingImportStore {
    static let appGroupID = "group.com.proportion.app"

    let directory: URL?

    init(appGroupID: String = PendingImportStore.appGroupID) {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        directory = base?.appendingPathComponent("pending-imports", isDirectory: true)
    }

    var isAvailable: Bool { directory != nil }

    func save(_ item: PendingImport, images: [Data] = []) throws {
        guard let directory else { throw StoreError.noAppGroup }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var item = item
        item.imageFileNames = []
        for (index, data) in images.enumerated() {
            let name = "\(item.id.uuidString)-\(index).jpg"
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            item.imageFileNames.append(name)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        try data.write(to: directory.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)
    }

    func loadAll() -> [PendingImport] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PendingImport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func imageData(for item: PendingImport) -> [Data] {
        guard let directory else { return [] }
        return item.imageFileNames.compactMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
    }

    func remove(_ item: PendingImport) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(item.id.uuidString).json"))
        for name in item.imageFileNames {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    enum StoreError: Error {
        case noAppGroup
    }
}
