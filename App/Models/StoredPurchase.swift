import Foundation
import SwiftData
import VaultCore

/// Persistence record. Deliberately stores primitives rather than VaultCore
/// value types, so the storage schema and the domain model can evolve
/// independently. Mapping lives in PurchaseMapping.swift.
@Model
final class StoredPurchase {
    var id: UUID = UUID()
    var merchant: String = ""
    var purchaseDate: Date = Date()
    var totalCentsRaw: Int = 0
    var categoryRaw: String = PurchaseCategory.other.rawValue
    var printedWindowDays: Int?
    var userWindowDays: Int?
    var printedWarrantyMonths: Int?
    var userWarrantyMonths: Int?
    var note: String = ""

    init(
        merchant: String,
        purchaseDate: Date,
        totalCents: Cents,
        category: PurchaseCategory,
        note: String = ""
    ) {
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.totalCentsRaw = totalCents.raw
        self.categoryRaw = category.rawValue
        self.note = note
    }

    var category: PurchaseCategory {
        get { PurchaseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var totalCents: Cents {
        get { Cents(totalCentsRaw) }
        set { totalCentsRaw = newValue.raw }
    }
}
