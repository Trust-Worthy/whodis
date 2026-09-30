import Foundation

/// One contact card whodis wrote, recorded so `--undo` can reverse it.
public struct ManifestEntry: Codable, Equatable {
    public enum Action: String, Codable {
        /// whodis made a brand-new card. Undo deletes it.
        case created
        /// A nameless card already existed; whodis filled in the name. Undo blanks the name again.
        case updated
    }

    public var contactIdentifier: String
    public var action: Action
    public var handles: [String]
    public var name: PersonName
    public var date: Date

    public init(contactIdentifier: String, action: Action, handles: [String], name: PersonName, date: Date = Date()) {
        self.contactIdentifier = contactIdentifier
        self.action = action
        self.handles = handles
        self.name = name
        self.date = date
    }
}

/// Append-only log at ~/Library/Application Support/whodis/manifest.json.
/// It holds names and numbers, so it's written 0600 (owner-only).
public struct Manifest: Codable, Equatable {
    public var entries: [ManifestEntry]

    public init(entries: [ManifestEntry] = []) {
        self.entries = entries
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("whodis/manifest.json")
    }

    public static func load(from url: URL = Manifest.defaultURL) throws -> Manifest {
        guard FileManager.default.fileExists(atPath: url.path) else { return Manifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL = Manifest.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
