import Foundation
import Testing
@testable import VaultCore

@Test("A known retailer maps to its own returns host")
func knownRetailer() {
    let url = RetailerLinks.returnsURL(forMerchant: "Best Buy")
    #expect(url?.host()?.contains("bestbuy.com") == true)
    #expect(RetailerLinks.isKnown("BEST BUY #1234"))
}

@Test("Matching is case- and noise-insensitive via substring")
func fuzzyMatch() {
    #expect(RetailerLinks.returnsURL(forMerchant: "the home depot #4172")?.host()?.contains("homedepot.com") == true)
    #expect(RetailerLinks.returnsURL(forMerchant: "Apple Store")?.host()?.contains("apple.com") == true)
}

@Test("An unknown merchant falls back to a web search, never nil")
func unknownFallsBackToSearch() {
    let url = RetailerLinks.returnsURL(forMerchant: "Bob's Corner Store")
    #expect(url != nil)
    #expect(url?.host()?.contains("google.com") == true)
    #expect(url?.absoluteString.contains("return") == true)
    #expect(RetailerLinks.isKnown("Bob's Corner Store") == false)
}

@Test("An empty merchant yields no link")
func emptyMerchant() {
    #expect(RetailerLinks.returnsURL(forMerchant: "   ") == nil)
}
