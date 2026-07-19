import Testing
@testable import VaultCore

@Test("Durable goods categories are returnable", arguments: [
    PurchaseCategory.electronics,
    .appliances,
    .tools,
    .furniture,
    .apparel,
    .sportingGoods
])
func durableGoodsAreReturnable(category: PurchaseCategory) {
    #expect(category.isReturnable)
}

@Test("Consumable categories are not returnable", arguments: [
    PurchaseCategory.groceries,
    .fuel,
    .restaurant,
    .pharmacy
])
func consumablesAreNotReturnable(category: PurchaseCategory) {
    #expect(!category.isReturnable)
}

@Test("Unknown category defaults to returnable so windows are not silently dropped")
func otherIsReturnable() {
    #expect(PurchaseCategory.other.isReturnable)
}

@Test("Every category has a non-empty display name")
func allCategoriesHaveDisplayNames() {
    for category in PurchaseCategory.allCases {
        #expect(!category.displayName.isEmpty)
    }
}
