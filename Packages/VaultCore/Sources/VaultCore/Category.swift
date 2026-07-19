import Foundation

/// What kind of thing was bought. Determines whether a purchase gets a
/// return window at all.
///
/// `other` is deliberately returnable: failing to offer a window on
/// something the user could have returned is a worse error than offering
/// one they do not need. The user can always dismiss it.
public enum PurchaseCategory: String, Codable, Sendable, CaseIterable {
    case electronics
    case appliances
    case tools
    case furniture
    case apparel
    case sportingGoods
    case groceries
    case fuel
    case restaurant
    case pharmacy
    case other

    public var isReturnable: Bool {
        switch self {
        case .electronics, .appliances, .tools, .furniture, .apparel, .sportingGoods, .other:
            true
        case .groceries, .fuel, .restaurant, .pharmacy:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .electronics: "Electronics"
        case .appliances: "Appliances"
        case .tools: "Tools"
        case .furniture: "Furniture"
        case .apparel: "Apparel"
        case .sportingGoods: "Sporting Goods"
        case .groceries: "Groceries"
        case .fuel: "Fuel"
        case .restaurant: "Restaurant"
        case .pharmacy: "Pharmacy"
        case .other: "Other"
        }
    }
}
