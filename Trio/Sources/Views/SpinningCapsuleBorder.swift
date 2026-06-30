import SwiftUI

/// A capsule-shaped border whose dashed gap rotates around the perimeter while
/// `isActive`, then crossfades to a solid border when it turns off.
///
/// Drop it on any pill-shaped view via `.spinningCapsuleBorder(isActive:color:)`.
/// The rotation honours Reduce Motion (the active style is shown without spinning)
/// and stops cleanly when deactivated, so no animation lingers off-screen.
struct SpinningCapsuleBorder: ViewModifier {
    let isActive: Bool
    var color: Color
    var activeLineWidth: CGFloat = 2.5
    var idleLineWidth: CGFloat = 3
    /// Share of the perimeter occupied by the moving gap (0...1).
    var gapFraction: CGFloat = 0.3
    var spinDuration: Double = 1.333
    var crossfadeDuration: Double = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0
    @State private var perimeter: CGFloat = 200

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { perimeter = Self.capsulePerimeter(geo.size) }
                        .onChange(of: geo.size) { _, newSize in
                            perimeter = Self.capsulePerimeter(newSize)
                        }
                }
            )
            .overlay(
                Capsule().stroke(
                    color.opacity(0.4),
                    style: StrokeStyle(
                        lineWidth: isActive ? activeLineWidth : idleLineWidth,
                        lineCap: .round,
                        dash: isActive
                            ? [perimeter * (1 - gapFraction), perimeter * gapFraction]
                            : [perimeter + 10, 0],
                        dashPhase: dashPhase
                    )
                )
                .animation(.easeInOut(duration: crossfadeDuration), value: isActive)
            )
            // Re-runs (cancelling the previous run) whenever `isActive` flips, so we
            // never leak a stale animation or start a spin we should have cancelled.
            .task(id: isActive) {
                guard isActive, !reduceMotion else {
                    // Stop the perpetual spin and settle the phase.
                    withAnimation(.easeInOut(duration: crossfadeDuration)) { dashPhase = 0 }
                    return
                }

                // Reset the phase without animating, then rotate the gap forever.
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { dashPhase = 0 }

                withAnimation(.linear(duration: spinDuration).repeatForever(autoreverses: false)) {
                    dashPhase = -perimeter
                }
            }
    }

    /// Perimeter of a capsule: the two straight segments plus the two semicircular
    /// caps (π × the shorter dimension).
    private static func capsulePerimeter(_ size: CGSize) -> CGFloat {
        let major = max(size.width, size.height)
        let minor = min(size.width, size.height)
        return (2 * (major - minor) + .pi * minor).rounded()
    }
}

extension View {
    /// Adds an animated, spinning capsule border that activates with `isActive`.
    func spinningCapsuleBorder(isActive: Bool, color: Color) -> some View {
        modifier(SpinningCapsuleBorder(isActive: isActive, color: color))
    }
}
