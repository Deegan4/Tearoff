import AppIntents
import SwiftData
import Foundation
import VaultCore

/// A purchase exposed to Siri, Shortcuts, and Spotlight. Resolving the return
/// deadline here means the entity shown in system UI carries the same date the
/// app shows — no re-derivation by the caller.
struct PurchaseEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Purchase")
    static let defaultQuery = PurchaseEntityQuery()

    let id: UUID
    let merchant: String
    let purchaseDate: Date
    let totalCents: Int
    let returnDeadline: Date?

    var displayRepresentation: DisplayRepresentation {
        let amount = Cents(totalCents).formatted(currencyCode: "USD")
        if let returnDeadline {
            let by = returnDeadline.formatted(date: .abbreviated, time: .omitted)
            return DisplayRepresentation(title: "\(merchant)", subtitle: "\(amount) · return by \(by)")
        }
        return DisplayRepresentation(title: "\(merchant)", subtitle: "\(amount)")
    }

    @MainActor
    init(_ purchase: StoredPurchase) {
        id = purchase.id
        merchant = purchase.merchant
        purchaseDate = purchase.purchaseDate
        totalCents = purchase.totalCents.raw
        returnDeadline = ResolverStore.shared.returnWindow(for: purchase)?.deadline
    }
}

/// Backs `PurchaseEntity`. Reads from the shared SwiftData container, newest
/// first, so Shortcuts and Spotlight surface the user's real vault.
struct PurchaseEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PurchaseEntity] {
        let context = SharedModelContainer.shared.mainContext
        let wanted = Set(identifiers)
        let all = try context.fetch(FetchDescriptor<StoredPurchase>())
        return all.filter { wanted.contains($0.id) }.map(PurchaseEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PurchaseEntity] {
        let context = SharedModelContainer.shared.mainContext
        var descriptor = FetchDescriptor<StoredPurchase>(
            sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
        descriptor.fetchLimit = 20
        return try context.fetch(descriptor).map(PurchaseEntity.init)
    }
}
