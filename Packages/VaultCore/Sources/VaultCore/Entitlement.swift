import Foundation

/// Product identifiers for the three consumer tiers. Kept in VaultCore (not
/// the App) so the same constants back both the StoreKit layer and the pure
/// entitlement logic below, and so tests can reason about them without
/// importing StoreKit.
public enum TearoffProduct {
    public static let proMonthly = "com.tearoff.pro.monthly"
    public static let proYearly = "com.tearoff.pro.yearly"
    public static let proLifetime = "com.tearoff.pro.lifetime"

    /// Every identifier that grants Pro. A membership test, so adding a tier
    /// later is a one-line change here rather than scattered `||`s.
    public static let proGranting: Set<String> = [proMonthly, proYearly, proLifetime]
}

/// Which tier a user is on, derived purely from the set of currently-active
/// product identifiers. StoreKit owns the hard part — deciding which
/// transactions are unexpired and unrevoked (`Transaction.currentEntitlements`)
/// — and hands us the resulting identifiers. This layer just maps them to a
/// tier, which keeps the gate deterministic and unit-testable.
public enum ProTier: Equatable, Sendable {
    case free
    /// Pro via an auto-renewing subscription (monthly or yearly).
    case subscriber
    /// Pro via the one-time lifetime purchase. Outranks a subscription.
    case lifetime

    public var isPro: Bool { self != .free }
}

public enum Entitlement {
    /// Resolve the tier from the active identifiers. Lifetime wins over a
    /// subscription (a user who bought lifetime should never see a renewal or
    /// a paywall, even if a stale sub identifier lingers).
    public static func tier(activeProductIDs: Set<String>) -> ProTier {
        if activeProductIDs.contains(TearoffProduct.proLifetime) { return .lifetime }
        if !activeProductIDs.isDisjoint(with: TearoffProduct.proGranting) { return .subscriber }
        return .free
    }

    public static func isPro(activeProductIDs: Set<String>) -> Bool {
        tier(activeProductIDs: activeProductIDs).isPro
    }
}
