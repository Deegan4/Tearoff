import Testing
@testable import VaultCore

@Test("Cents stores exact integer minor units")
func centsStoresExactValue() {
    #expect(Cents(1999).raw == 1999)
}

@Test("Cents addition is exact")
func centsAddition() {
    #expect((Cents(1999) + Cents(1)).raw == 2000)
}

@Test("Cents subtraction is exact")
func centsSubtraction() {
    #expect((Cents(2000) - Cents(1)).raw == 1999)
}

@Test("Cents multiplication by quantity is exact")
func centsMultiplication() {
    #expect((Cents(333) * 3).raw == 999)
}

@Test("Cents formats as USD currency")
func centsFormatsUSD() {
    #expect(Cents(1999).formatted(currencyCode: "USD") == "$19.99")
}

@Test("Cents formats negative amounts (coupon lines)")
func centsFormatsNegative() {
    #expect(Cents(-500).formatted(currencyCode: "USD") == "-$5.00")
}
