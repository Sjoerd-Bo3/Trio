import SwiftUI

// Capsule (pill-shaped) border helpers, built on the shared `SpinningCapsuleBorder`
// engine in SpinningCapsuleBorder.swift. Used by the loop and pump reservoir pills.
extension View {
    /// Animated, spinning **capsule** (pill) border that activates with `isActive`.
    func spinningCapsuleBorder(isActive: Bool, color: Color, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(isActive: isActive, color: color, lineWidth: lineWidth, cornerRadius: nil))
    }

    /// Determinate **capsule** (pill) progress border: a bright stroke fills the top and
    /// bottom edges symmetrically left → right as `progress` (0...1) approaches 1.
    func progressCapsuleBorder(progress: Double, color: Color, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(
            isActive: false,
            color: color,
            lineWidth: lineWidth,
            cornerRadius: nil,
            progress: CGFloat(progress)
        ))
    }
}
