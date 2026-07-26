import Foundation

/// A single queued snooze: push a purchase's return reminder out to a new
/// date. Mirrors `PendingReturnStore`'s handoff — the widget's snooze button
/// runs in the widget extension process and can't touch SwiftData or
/// `UNUserNotificationCenter` reliably, so it enqueues here; the app applies
/// the new reminder time on next foreground.
public struct PendingSnooze: Codable, Equatable, Sendable {
    public var purchaseID: String
    public var until: Date

    public init(purchaseID: String, until: Date) {
        self.purchaseID = purchaseID
        self.until = until
    }
}

/// Durable queue of pending snoozes in the shared App Group container, like
/// `PendingReturnStore`. Pure Foundation so it lives in VaultCore.
public struct PendingSnoozeStore {
    public static let storageKey = "pending-snoozes.json"

    private let fileURL: URL?

    public init(appGroupID: String = SharedDigestStore.appGroupID) {
        fileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: PendingSnoozeStore.storageKey)
    }

    public init(directory: URL) {
        fileURL = directory.appending(path: PendingSnoozeStore.storageKey)
    }

    public func pending() -> [PendingSnooze] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PendingSnooze].self, from: data)) ?? []
    }

    /// Queue (or replace) a snooze for a purchase. Only the latest request per
    /// purchase matters, so a repeat tap before the app drains it just updates
    /// the date rather than stacking entries.
    @discardableResult
    public func enqueue(purchaseID: String, until: Date) -> Bool {
        var entries = pending().filter { $0.purchaseID != purchaseID }
        entries.append(PendingSnooze(purchaseID: purchaseID, until: until))
        return write(entries)
    }

    @discardableResult
    public func remove(_ applied: [String]) -> Bool {
        let done = Set(applied)
        return write(pending().filter { !done.contains($0.purchaseID) })
    }

    @discardableResult
    private func write(_ entries: [PendingSnooze]) -> Bool {
        guard let fileURL else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
