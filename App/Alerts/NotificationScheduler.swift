import Foundation
import UserNotifications
import VaultCore

actor NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Identifiers are deterministic per purchase, so re-scheduling after a
    /// correction replaces the pending request instead of duplicating it.
    private func identifier(_ id: UUID, _ kind: String) -> String {
        "purchase-\(id.uuidString)-\(kind)"
    }

    func schedule(
        purchaseID: UUID,
        merchant: String,
        returnWindow: WindowResolution?,
        warranty: WindowResolution?
    ) async {
        await cancel(purchaseID: purchaseID)

        if let window = returnWindow {
            await add(
                id: identifier(purchaseID, "return"),
                title: "Return window closing",
                body: "Your \(merchant) return window closes in 3 days.",
                fireDate: Calendar.utcGregorian.date(byAdding: .day, value: -3, to: window.deadline)
            )
        }

        if let warranty {
            await add(
                id: identifier(purchaseID, "warranty"),
                title: "Warranty expiring",
                body: "Your \(merchant) purchase leaves warranty in 30 days.",
                fireDate: Calendar.utcGregorian.date(byAdding: .day, value: -30, to: warranty.deadline)
            )
        }
    }

    func cancel(purchaseID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [
            identifier(purchaseID, "return"),
            identifier(purchaseID, "warranty")
        ])
    }

    private func add(id: String, title: String, body: String, fireDate: Date?) async {
        guard let fireDate, fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
