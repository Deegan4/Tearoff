import AppIntents
import WidgetKit
import VaultCore

/// The Home Screen widget's "Snooze 3 days" button (Pro, alongside Mark
/// Returned). Doesn't touch the real deadline — it only pushes the *reminder*
/// notification out, queued here for the app to apply on next foreground,
/// same handoff pattern as `MarkReturnedIntent`.
///
/// Lives in `Shared/` so it's compiled into both the app and widget targets.
struct SnoozeIntent: AppIntent {
    static let title: LocalizedStringResource = "Snooze Reminder"
    static let description = IntentDescription("Push a Tearoff return reminder out by a few days.")
    static let openAppWhenRun = false

    @Parameter(title: "Purchase")
    var purchaseID: String

    init() {}
    init(purchaseID: String) { self.purchaseID = purchaseID }

    func perform() async throws -> some IntentResult {
        let until = Calendar.utcGregorian.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        PendingSnoozeStore().enqueue(purchaseID: purchaseID, until: until)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
