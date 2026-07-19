import Foundation

/// Where a window came from. Always surfaced in the UI.
public enum Provenance: String, Codable, Sendable, CaseIterable {
    /// Read off the receipt itself. The most authoritative source available,
    /// because it is the actual contract.
    case printed
    /// Matched against the curated retailer policy table.
    case table
    /// Inferred from the product category. An estimate, and labelled as one.
    case categoryDefault
    /// Entered or corrected by the user.
    case user

    public var explanation: String {
        switch self {
        case .printed: "printed on your receipt"
        case .table: "\(Self.tableSourceName) return policy"
        case .categoryDefault: "typical for this category — estimate"
        case .user: "you set this"
        }
    }

    public var isEstimate: Bool {
        self == .categoryDefault
    }

    static let tableSourceName = "published"
}
