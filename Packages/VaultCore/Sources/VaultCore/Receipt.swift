import Foundation

/// One parsed line off a receipt: a product name and its price in cents.
/// A plain value type so it is shared between the parser (which produces it)
/// and persistence (which stores it as JSON on the purchase record).
public struct LineItem: Codable, Hashable, Sendable {
    public var name: String
    public var cents: Int

    public init(name: String, cents: Int) {
        self.name = name
        self.cents = cents
    }
}

/// The fields we try to lift off a receipt. Everything is optional because
/// OCR is best-effort; the user confirms/corrects on the printed slip.
public struct ParsedReceipt: Equatable, Sendable {
    public var merchant: String
    public var date: Date?
    public var totalCents: Cents?
    /// Inferred from merchant/keywords. `nil` means "no confident guess" —
    /// the form keeps its default rather than forcing `.other`.
    public var category: PurchaseCategory?
    /// A return term printed on the slip, e.g. "return within 30 days".
    public var printedReturnDays: Int?
    /// A warranty term printed on the slip, e.g. "1 year warranty".
    public var printedWarrantyMonths: Int?
    /// Amount breakdown, when the slip labels them.
    public var subtotalCents: Cents?
    public var taxCents: Cents?
    /// Tender, e.g. "Visa ••••1234" or "Cash".
    public var paymentMethod: String?
    /// The order/transaction/receipt number a store asks for on a return.
    public var orderNumber: String?
    /// Best-effort product lines (name + price in cents).
    public var lineItems: [LineItem]

    public init(
        merchant: String,
        date: Date? = nil,
        totalCents: Cents? = nil,
        category: PurchaseCategory? = nil,
        printedReturnDays: Int? = nil,
        printedWarrantyMonths: Int? = nil,
        subtotalCents: Cents? = nil,
        taxCents: Cents? = nil,
        paymentMethod: String? = nil,
        orderNumber: String? = nil,
        lineItems: [LineItem] = []
    ) {
        self.merchant = merchant
        self.date = date
        self.totalCents = totalCents
        self.category = category
        self.printedReturnDays = printedReturnDays
        self.printedWarrantyMonths = printedWarrantyMonths
        self.subtotalCents = subtotalCents
        self.taxCents = taxCents
        self.paymentMethod = paymentMethod
        self.orderNumber = orderNumber
        self.lineItems = lineItems
    }
}
