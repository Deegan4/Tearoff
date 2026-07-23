import SwiftUI

/// House motion tokens. "Premium" means weighted and unhurried with only a
/// hint of overshoot — the opposite of a bouncy toy. Tune these in one place
/// and the whole app moves together.
enum Motion {
    /// Default premium spring: settles with a barely-there overshoot.
    static let premium = Animation.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)

    /// Snappier variant for small, frequent state flips (toggles, selection).
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0)

    /// Slow, cinematic reveal for first-appearance content.
    static let reveal = Animation.spring(response: 0.62, dampingFraction: 0.88, blendDuration: 0)
}
