import AppIntents
import Foundation
import VaultCore

/// "Log a receipt" — opens the app to the manual add form.
struct LogReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Receipt"
    static let description = IntentDescription("Open Tearoff to add a purchase and track its return window.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pendingRoute = .add
        return .result()
    }
}

/// "Scan a receipt" — opens the app to the camera scanner (Pro-gated in the UI,
/// which shows the paywall for free users).
struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Receipt"
    static let description = IntentDescription("Open Tearoff's camera to scan a paper receipt.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pendingRoute = .scan
        return .result()
    }
}

/// "What's my next deadline" — answers with the soonest return/warranty
/// deadline, spoken/shown by Siri without opening the app. Reads the shared
/// digest the app already publishes for the widget, so no model load is needed.
struct NextDeadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Deadline"
    static let description = IntentDescription("Ask Tearoff which return or warranty window is closing next.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = SharedDigestStore().read()?.deadlines.first else {
            return .result(dialog: "You have no upcoming deadlines in Tearoff.")
        }
        let days = DeadlineDigest.daysRemaining(to: next.deadline, from: Date())
        let kind = next.kind == .returnWindow ? "return window" : "warranty"
        let when: String
        switch days {
        case ..<0: when = "has already passed"
        case 0: when = "closes today"
        case 1: when = "closes tomorrow"
        default: when = "closes in \(days) days"
        }
        return .result(dialog: "\(next.merchant)'s \(kind) \(when).")
    }
}
