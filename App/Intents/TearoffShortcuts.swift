import AppIntents

/// System-suggested Siri phrases. These register the app's intents with
/// Shortcuts and Spotlight so the user can say "Log a receipt in Tearoff" or
/// ask "What's my next deadline in Tearoff" without any setup.
struct TearoffShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogReceiptIntent(),
            phrases: [
                "Log a receipt in \(.applicationName)",
                "Add a purchase to \(.applicationName)",
                "New receipt in \(.applicationName)",
            ],
            shortTitle: "Log Receipt",
            systemImageName: "doc.text")

        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "Scan a receipt with \(.applicationName)",
                "Scan a receipt in \(.applicationName)",
            ],
            shortTitle: "Scan Receipt",
            systemImageName: "camera")

        AppShortcut(
            intent: NextDeadlineIntent(),
            phrases: [
                "What's my next deadline in \(.applicationName)",
                "Show my next \(.applicationName) deadline",
                "When does my next return close in \(.applicationName)",
            ],
            shortTitle: "Next Deadline",
            systemImageName: "clock.badge.exclamationmark")
    }
}
