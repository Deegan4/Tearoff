import ActivityKit
import Foundation
import VaultCore

/// Starts, updates, and ends the return-countdown Live Activity. Policy: show
/// one for the single soonest open return that closes within 48 hours; end it
/// once nothing qualifies (resolved, passed, or now further out).
@MainActor
enum LiveActivityManager {
    private static let windowHours: TimeInterval = 48 * 60 * 60

    /// Reconcile Live Activities with the current vault. Idempotent — safe to
    /// call on every vault change. Computes the target on the main actor (from
    /// SwiftData), then reduces to Sendable values before the async ActivityKit
    /// calls so nothing non-Sendable crosses a boundary.
    static func sync(_ purchases: [StoredPurchase]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date()
        let soonest = purchases
            .filter { !$0.status.isResolved }
            .compactMap { p -> (id: String, merchant: String, deadline: Date)? in
                guard let w = ResolverStore.shared.returnWindow(for: p),
                      w.deadline >= now,
                      w.deadline.timeIntervalSince(now) <= windowHours else { return nil }
                return (p.id.uuidString, p.merchant, w.deadline)
            }
            .min { $0.deadline < $1.deadline }

        let active = Activity<ReturnActivityAttributes>.activities

        guard let soonest else {
            for activity in active {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let content = ActivityContent(
            state: ReturnActivityAttributes.ContentState(deadline: soonest.deadline),
            staleDate: soonest.deadline)

        // Update the target in place; end everything else. Using the loop
        // binding (not a captured `first(where:)` result) keeps each Activity in
        // its own isolation region, so nothing is "sent" across a boundary.
        var updatedTarget = false
        for activity in active {
            if activity.attributes.purchaseID == soonest.id {
                await activity.update(content)
                updatedTarget = true
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        if !updatedTarget {
            let attributes = ReturnActivityAttributes(purchaseID: soonest.id, merchant: soonest.merchant)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }
}
