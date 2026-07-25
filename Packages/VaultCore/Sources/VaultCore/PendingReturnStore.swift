import Foundation

/// A tiny durable queue of purchase ids that the user marked "returned" from a
/// place that can't touch SwiftData — namely the Home Screen widget's
/// interactive button, whose intent runs in the widget extension process. The
/// intent enqueues here; the app drains it on next foreground and applies the
/// status change (and cancels the alerts) against the real store.
///
/// Backed by a JSON file in the shared App Group container, like
/// `SharedDigestStore`, so both processes see the same queue. Pure Foundation
/// (no WidgetKit, SwiftData, or UI) so it lives in VaultCore and is unit
/// testable with an injected directory.
public struct PendingReturnStore {
    /// Filename inside the container.
    public static let storageKey = "pending-returns.json"

    private let fileURL: URL?

    /// Defaults to the shared App Group container. Tests pass an explicit
    /// directory so they can run without an App Group entitlement.
    public init(appGroupID: String = SharedDigestStore.appGroupID) {
        fileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: PendingReturnStore.storageKey)
    }

    /// Point the store at an arbitrary directory (used by tests).
    public init(directory: URL) {
        fileURL = directory.appending(path: PendingReturnStore.storageKey)
    }

    /// Currently queued purchase ids, in insertion order.
    public func pending() -> [String] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Add a purchase id to the queue. De-duplicates, so tapping twice before
    /// the app drains it only applies once.
    @discardableResult
    public func enqueue(_ purchaseID: String) -> Bool {
        var ids = pending()
        guard !ids.contains(purchaseID) else { return true }
        ids.append(purchaseID)
        return write(ids)
    }

    /// Remove ids the app has finished applying, leaving any that arrived after
    /// the drain started so nothing is silently dropped.
    @discardableResult
    public func remove(_ applied: [String]) -> Bool {
        let done = Set(applied)
        return write(pending().filter { !done.contains($0) })
    }

    @discardableResult
    private func write(_ ids: [String]) -> Bool {
        guard let fileURL else { return false }
        do {
            try JSONEncoder().encode(ids).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
