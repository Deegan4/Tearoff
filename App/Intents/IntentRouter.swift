import Observation

/// A tiny signal bus so App Intents (Siri / Shortcuts) can ask the running app
/// to navigate. An intent sets `pendingRoute`; `VaultView` observes it and
/// presents the matching screen, then clears it.
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    enum Route: Equatable {
        case add      // open the manual add form
        case scan     // open the camera scanner (Pro-gated in the UI)
    }

    var pendingRoute: Route?

    private init() {}
}
