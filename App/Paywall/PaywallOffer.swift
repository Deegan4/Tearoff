import Foundation
import StoreKit
import VaultCore

/// What the paywall actually needs to draw a purchase row: an identifier, a
/// name, and a price string. StoreKit's `Product` supplies all three in the
/// shipping app.
///
/// The indirection exists because `Product` cannot be constructed — it only
/// arrives from the App Store — and App Store Connect requires a screenshot of
/// the purchase screen *before* it will serve the products to StoreKit. Drawing
/// from a value type lets a Debug build render the real paywall with the real
/// configured prices to break that circle. See `PaywallOffer.placeholders`.
struct PaywallOffer: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String

    init(id: String, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }

    init(_ product: Product) {
        self.init(id: product.id,
                  displayName: product.displayName,
                  displayPrice: product.displayPrice)
    }
}

#if DEBUG
extension PaywallOffer {
    /// The three Pro offers as configured in App Store Connect and mirrored in
    /// `Tearoff.storekit`. Debug-only, and shown only when launched with
    /// `SIMCTL_CHILD_TEAROFF_PLACEHOLDER_OFFERS=1` — its sole purpose is
    /// capturing the App Store Connect review screenshot, which cannot be
    /// captured from a live StoreKit fetch until that screenshot exists.
    static let placeholders: [PaywallOffer] = [
        PaywallOffer(id: TearoffProduct.proMonthly,
                     displayName: "Tearoff Pro — Monthly", displayPrice: "$2.99"),
        PaywallOffer(id: TearoffProduct.proYearly,
                     displayName: "Tearoff Pro — Yearly", displayPrice: "$14.99"),
        PaywallOffer(id: TearoffProduct.proLifetime,
                     displayName: "Tearoff Pro — Lifetime", displayPrice: "$39.99"),
    ]
}
#endif
