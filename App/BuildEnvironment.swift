import Foundation
import StoreKit

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
@MainActor
enum BuildEnvironment {
    /// Whether this install came from TestFlight (or a local sandbox).
    ///
    /// Resolved from `AppTransaction`, which is async, so this starts `false`
    /// and is filled in by `resolve()` at launch. **The default has to be the
    /// locked one**: a window where an App Store build reported `true` would
    /// hand out Pro for free, whereas a window where TestFlight reports
    /// `false` only means a tester sees the Developer section appear a moment
    /// late. Errs toward locked, never toward unlocked.
    private(set) static var isTestFlight = false

    /// Whether developer-only controls may be shown *and honoured*.
    ///
    /// Both the UI and `StoreManager.isPro` consult this, so an App Store
    /// build cannot be coaxed into a Pro unlock even if a stale
    /// `UserDefaults` value survives from a TestFlight install on the same
    /// device.
    static var allowsDeveloperTools: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
    }

    /// Read the app's own transaction to learn which storefront installed it.
    /// Call once at launch. Replaces the receipt-URL sniff
    /// (`appStoreReceiptURL`), deprecated in iOS 18.
    ///
    /// A failure here leaves `isTestFlight` false, which is the safe side.
    static func resolve() async {
        guard let transaction = try? await AppTransaction.shared.payloadValue else { return }
        // TestFlight builds and local sandbox installs both report `.sandbox`;
        // an App Store install reports `.production`. `.xcode` only occurs in
        // Debug, where the gate is open anyway.
        isTestFlight = transaction.environment != .production
    }
}
