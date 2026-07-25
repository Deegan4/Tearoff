import AppIntents
import WidgetKit
import VaultCore

/// The Home Screen widget's "Mark returned" button. Runs in place (no app
/// launch): in the widget extension when the app is backgrounded, or in the app
/// process when it's running. Neither can be guaranteed to reach SwiftData from
/// the widget process, so the intent doesn't mutate the store itself — it
/// enqueues the purchase for the app to resolve (`PendingReturnStore`) and
/// optimistically drops the purchase's rows from the shared digest so the
/// widget reflects the tap immediately. The app applies the real status change
/// and cancels the alerts the next time it comes to the foreground.
///
/// Lives in `Shared/` so it's compiled into both the app and widget targets.
struct MarkReturnedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Returned"
    static let description = IntentDescription("Mark a purchase as returned from the Tearoff widget.")
    /// Act in place — the whole point is not to bounce the user into the app.
    static let openAppWhenRun = false

    @Parameter(title: "Purchase")
    var purchaseID: String

    init() {}
    init(purchaseID: String) { self.purchaseID = purchaseID }

    func perform() async throws -> some IntentResult {
        // Queue for the app to apply against SwiftData (+ cancel notifications).
        PendingReturnStore().enqueue(purchaseID)

        // Optimistically remove this purchase's deadlines from the widget digest
        // so the Home Screen updates now, before the app next runs.
        let store = SharedDigestStore()
        if let digest = store.read() {
            let remaining = digest.deadlines.filter { $0.purchaseID != purchaseID }
            if remaining.count != digest.deadlines.count {
                store.write(DeadlineDigest(generatedAt: digest.generatedAt, deadlines: remaining))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
