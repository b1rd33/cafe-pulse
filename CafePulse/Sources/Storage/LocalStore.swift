import Foundation

actor LocalStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let snapshotURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = baseURL.appendingPathComponent("CafePulse", isDirectory: true)
        snapshotURL = directoryURL.appendingPathComponent("snapshot.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // No key strategy — models use explicit CodingKeys for snake_case mapping

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // No key strategy — models use explicit CodingKeys for snake_case mapping
    }

    func loadSnapshot() throws -> AppSnapshot {
        try ensureDirectory()

        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return AppSnapshot()
        }

        let data = try Data(contentsOf: snapshotURL)
        return try decoder.decode(AppSnapshot.self, from: data)
    }

    func persist(_ snapshot: AppSnapshot) throws {
        try ensureDirectory()
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
