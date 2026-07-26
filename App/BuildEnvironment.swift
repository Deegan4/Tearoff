import Foundation

/// Which build this is running as, for gating developer-only affordances.
///
/// The Developer section used to be `#if DEBUG`, which meant it disappeared
/// from the Release builds that go to TestFlight — exactly where it is most
/// needed, since a TestFlight tester can't reach Pro features until the
/// products are purchasable.
///
/// This widens the gate to TestFlight while keeping it firmly shut on the App
/// Store: a shipped build that could unlock Pro for free would be both an
/// App Review problem and a hole straight through the business model.
enum BuildEnvironment {
    /// TestFlight and sandbox installs receive a `sandboxReceipt`; App Store
    /// installs receive a `receipt`. Evaluated once — the receipt path does
    /// not change during a run.
    static let isTestFlight: Bool = {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }()

    /// Whether developer-only controls may be shown *and honoured*.
    ///
    /// Both the UI and `StoreManager.isPro` consult this, so an App Store
    /// build cannot be coaxed into a Pro unlock even if a stale
    /// `UserDefaults` value survives from a TestFlight install on the same
    /// device.
    static let allowsDeveloperTools: Bool = {
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
    }()
}
