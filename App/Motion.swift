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

    /// Edge-of-playful: a touch more overshoot for moments that should feel
    /// alive (empty states, staggered reveals) without going full bounce.
    static let alive = Animation.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0)
}

/// Fades and lifts a view in on first appearance, offset by `index` so a
/// stack of them cascades. Uses `withAnimation` in `onAppear` so the delay is
/// honoured per element.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(Motion.alive.delay(Double(index) * 0.07)) { shown = true }
            }
    }
}

extension View {
    /// Cascading fade-and-lift entrance. Pass the element's position.
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// Press feedback for card-shaped buttons. `.buttonStyle(.plain)` renders a
/// tappable card with *no* pressed state at all, which reads as broken on a
/// primary action; this restores a weighted press without the default button
/// chrome. The scale is gated on Reduce Motion — SwiftUI does not disable
/// custom animations automatically — while the opacity dip always applies, so
/// the press stays perceivable either way.
struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardButtonStyle {
    /// Card press feedback — use instead of `.plain` on tappable cards.
    static var pressableCard: PressableCardButtonStyle { .init() }
}
