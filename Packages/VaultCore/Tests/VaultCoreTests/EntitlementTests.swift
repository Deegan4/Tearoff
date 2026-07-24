import Testing
@testable import VaultCore

@Test("No active products means the free tier")
func noProductsIsFree() {
    #expect(Entitlement.tier(activeProductIDs: []) == .free)
    #expect(Entitlement.isPro(activeProductIDs: []) == false)
}

@Test("A monthly or yearly subscription grants Pro as a subscriber")
func subscriptionGrantsPro() {
    #expect(Entitlement.tier(activeProductIDs: [TearoffProduct.proMonthly]) == .subscriber)
    #expect(Entitlement.tier(activeProductIDs: [TearoffProduct.proYearly]) == .subscriber)
    #expect(Entitlement.isPro(activeProductIDs: [TearoffProduct.proYearly]))
}

@Test("The lifetime purchase grants the lifetime tier")
func lifetimeGrantsLifetime() {
    #expect(Entitlement.tier(activeProductIDs: [TearoffProduct.proLifetime]) == .lifetime)
    #expect(Entitlement.isPro(activeProductIDs: [TearoffProduct.proLifetime]))
}

@Test("Lifetime outranks a lingering subscription identifier")
func lifetimeOutranksSubscription() {
    let ids: Set<String> = [TearoffProduct.proLifetime, TearoffProduct.proMonthly]
    #expect(Entitlement.tier(activeProductIDs: ids) == .lifetime)
}

@Test("An unrelated identifier does not grant Pro")
func unknownIdentifierIsFree() {
    #expect(Entitlement.tier(activeProductIDs: ["com.tearoff.something.else"]) == .free)
}
