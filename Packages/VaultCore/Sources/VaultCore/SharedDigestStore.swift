import Foundation

/// Reads/writes the widget's `DeadlineDigest` in a shared App Group container,
/// the handoff point between the app (writer) and the widget extension
/// (reader). Pure Foundation — no WidgetKit or UI — so it lives in VaultCore
/// and both targets share one implementation.
public struct SharedDigestStore {
    public static let appGroupID = "group.com.tearoff.vault"

    private let fileURL: URL?

    public init(appGroupID: String = SharedDigestStore.appGroupID) {
        fileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: DeadlineDigest.storageKey)
    }

    @discardableResult
    public func write(_ digest: DeadlineDigest) -> Bool {
        guard let fileURL else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(digest).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func read() -> DeadlineDigest? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DeadlineDigest.self, from: data)
    }
}
