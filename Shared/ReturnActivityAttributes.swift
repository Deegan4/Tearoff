import ActivityKit
import Foundation

/// Shared between the app (which starts/updates the activity) and the widget
/// extension (which renders it), so it's compiled into both targets. Describes
/// a live countdown to a return deadline for a single purchase.
struct ReturnActivityAttributes: ActivityAttributes {
    /// The parts that change over the activity's life.
    struct ContentState: Codable, Hashable {
        var deadline: Date
    }

    /// Fixed for the life of the activity.
    var purchaseID: String
    var merchant: String
}
