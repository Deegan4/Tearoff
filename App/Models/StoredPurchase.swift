import Foundation
import SwiftData
import VaultCore

/// Where a purchase is in its return/warranty life. Anything other than
/// `active` is "resolved" — it no longer needs reminders and stops nagging.
enum PurchaseStatus: String, Codable, CaseIterable, Identifiable {
    case active, returned, refunded, kept

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: "Active"
        case .returned: "Returned"
        case .refunded: "Refunded"
        case .kept: "Kept"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "clock"
        case .returned: "arrow.uturn.backward"
        case .refunded: "dollarsign.arrow.circlepath"
        case .kept: "checkmark.seal"
        }
    }

    /// Resolved purchases are done with their window and need no alerts.
    var isResolved: Bool { self != .active }
}

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
    /// Lifecycle state. Defaults to active; a default keeps lightweight
    /// migration (and future CloudKit sync) happy.
    var statusRaw: String = PurchaseStatus.active.rawValue

    /// The scanned receipt image, downsampled. Held in external storage so the
    /// SwiftData store stays small; `nil` for manually-entered purchases.
    @Attribute(.externalStorage) var receiptImageData: Data?

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

    var status: PurchaseStatus {
        get { PurchaseStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}
