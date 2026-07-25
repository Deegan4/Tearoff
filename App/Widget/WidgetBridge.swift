import Foundation
import WidgetKit
import VaultCore

/// Publishes the vault's upcoming deadlines to the shared App Group container
/// and asks WidgetKit to reload. Called whenever the vault changes so the Home
/// Screen widget stays current without the widget ever reading SwiftData.
@MainActor
enum WidgetBridge {
    private static let store = SharedDigestStore()

    /// Flatten active purchases into their resolved, still-open return and
    /// warranty deadlines, build the digest, persist, and reload timelines.
    static func publish(_ purchases: [StoredPurchase]) {
        var deadlines: [UpcomingDeadline] = []
        for p in purchases where !p.status.isResolved {
            if let r = ResolverStore.shared.returnWindow(for: p) {
                deadlines.append(UpcomingDeadline(
                    id: UpcomingDeadline.makeID(purchaseID: p.id, kind: .returnWindow),
                    merchant: p.merchant,
                    kind: .returnWindow,
                    deadline: r.deadline,
                    isEstimate: r.provenance.isEstimate
                ))
            }
            if let w = ResolverStore.shared.warrantyWindow(for: p) {
                deadlines.append(UpcomingDeadline(
                    id: UpcomingDeadline.makeID(purchaseID: p.id, kind: .warranty),
                    merchant: p.merchant,
                    kind: .warranty,
                    deadline: w.deadline,
                    isEstimate: w.provenance.isEstimate
                ))
            }
        }
        let digest = DeadlineDigest.build(from: deadlines, now: Date())
        store.write(digest)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
