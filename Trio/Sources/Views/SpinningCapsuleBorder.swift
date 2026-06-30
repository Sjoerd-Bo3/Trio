import SwiftUI
import UIKit

/// A `UIView` that strokes a rounded/capsule dashed border in a `CAShapeLayer`
/// and animates `lineDashPhase` with a `CABasicAnimation`.
///
/// Animating the dash phase through CoreAnimation runs the rotation on the
/// render server (off the main thread), unlike animating a SwiftUI
/// `StrokeStyle.dashPhase`, which re-rasterises the path every frame on the
/// main thread and causes micro-stutter on a busy screen.
final class DashedSpinnerBorderView: UIView {
    private let shape = CAShapeLayer()
    private var spinning = false
    private var perimeter: CGFloat = 0

    var strokeColor: UIColor = .systemGray { didSet { applyColor() } }
    var lineWidth: CGFloat = 2 { didSet { shape.lineWidth = lineWidth; setNeedsLayout() } }
    /// `nil` → capsule (corner radius = half the shorter side).
    var cornerRadius: CGFloat? { didSet { setNeedsLayout() } }
    /// Share of the perimeter occupied by the moving gap (0...1).
    var gapFraction: CGFloat = 0.3
    var spinDuration: CFTimeInterval = 1.333
    /// Non-nil switches the view to a **determinate** progress ring (0...1): the
    /// stroke fills along the perimeter and the open gap closes as it approaches 1.
    /// `nil` → indeterminate spinning gap (driven by `setSpinning`).
    var progress: CGFloat? { didSet { applyMode() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillColor = UIColor.clear.cgColor
        shape.lineCap = .round
        shape.lineWidth = lineWidth
        layer.addSublayer(shape)
        applyColor()
        // CoreAnimation strips animations when the app backgrounds; re-add on return.
        // Fully qualified: Trio defines its own `NotificationCenter` protocol that
        // otherwise shadows Foundation's inside the Trio module.
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(reapplyAnimation),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) unavailable") }

    deinit { Foundation.NotificationCenter.default.removeObserver(self) }

    private func applyColor() { shape.strokeColor = strokeColor.withAlphaComponent(0.4).cgColor }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        let inset = lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(cornerRadius ?? min(rect.width, rect.height) / 2, min(rect.width, rect.height) / 2)
        shape.path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        // Rounded-rect perimeter: the straight segments + the four quarter-circle corners.
        perimeter = 2 * (rect.width - 2 * radius) + 2 * (rect.height - 2 * radius) + 2 * .pi * radius
        applyMode()
    }

    func setSpinning(_ on: Bool) {
        guard on != spinning else { return }
        spinning = on
        applyMode()
    }

    /// Picks the rendering mode from the current state: determinate progress ring
    /// when `progress` is set, otherwise the indeterminate spin / solid border.
    private func applyMode() {
        guard perimeter > 0 else { return }
        if let progress = progress {
            // Determinate: solid stroke trimmed to `progress`; the gap closes as it nears 1.
            shape.removeAnimation(forKey: "spin")
            shape.lineDashPattern = nil
            shape.lineDashPhase = 0
            shape.strokeStart = 0
            // Animate strokeEnd on the render server so progress steps ease smoothly.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            shape.strokeEnd = max(0, min(1, progress))
            CATransaction.commit()
        } else if spinning {
            shape.strokeStart = 0
            shape.strokeEnd = 1
            let gap = perimeter * gapFraction
            shape.lineDashPattern = [NSNumber(value: Double(perimeter - gap)), NSNumber(value: Double(gap))]
            reapplyAnimation()
        } else {
            shape.removeAnimation(forKey: "spin")
            shape.lineDashPattern = nil
            shape.lineDashPhase = 0
            shape.strokeStart = 0
            shape.strokeEnd = 1
        }
    }

    @objc private func reapplyAnimation() {
        guard spinning, progress == nil, perimeter > 0 else { return }
        shape.removeAnimation(forKey: "spin")
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = perimeter
        animation.duration = spinDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        shape.add(animation, forKey: "spin")
    }
}

private struct DashedSpinnerBorder: UIViewRepresentable {
    var isActive: Bool
    var color: Color
    var lineWidth: CGFloat
    var cornerRadius: CGFloat?
    /// Non-nil → determinate progress ring (ignores `isActive`/spin).
    var progress: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context _: Context) -> DashedSpinnerBorderView {
        let view = DashedSpinnerBorderView()
        configure(view)
        return view
    }

    func updateUIView(_ view: DashedSpinnerBorderView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: DashedSpinnerBorderView) {
        view.strokeColor = UIColor(color)
        view.lineWidth = lineWidth
        view.cornerRadius = cornerRadius
        if let progress = progress {
            // Determinate progress is not vestibular motion, so it stays on under Reduce Motion.
            view.setSpinning(false)
            view.progress = progress
        } else {
            view.progress = nil
            // Reduce Motion: keep the (solid) border, drop the rotation.
            view.setSpinning(isActive && !reduceMotion)
        }
    }
}

/// Overlays a dashed border whose gap rotates around the perimeter while
/// `isActive`, and shows a solid border otherwise. Reusable on any
/// pill-shaped or rounded-rectangle view.
struct SpinningCapsuleBorder: ViewModifier {
    let isActive: Bool
    var color: Color
    var lineWidth: CGFloat = 2
    /// `nil` → capsule; otherwise a rounded rectangle of this corner radius.
    var cornerRadius: CGFloat? = nil
    /// Non-nil → determinate progress ring (0...1) instead of an indeterminate spin.
    var progress: CGFloat? = nil

    func body(content: Content) -> some View {
        content.overlay(
            DashedSpinnerBorder(
                isActive: isActive,
                color: color,
                lineWidth: lineWidth,
                cornerRadius: cornerRadius,
                progress: progress
            )
        )
    }
}

extension View {
    /// Animated, spinning **capsule** (pill) border that activates with `isActive`.
    func spinningCapsuleBorder(isActive: Bool, color: Color, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(isActive: isActive, color: color, lineWidth: lineWidth, cornerRadius: nil))
    }

    /// Animated, spinning **rounded-rectangle** border that activates with `isActive`.
    func spinningRoundedBorder(isActive: Bool, color: Color, cornerRadius: CGFloat, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(isActive: isActive, color: color, lineWidth: lineWidth, cornerRadius: cornerRadius))
    }

    /// Determinate **capsule** (pill / circle) progress border: the stroke fills and the
    /// gap closes as `progress` (0...1) approaches 1. On a square frame this draws a ring.
    func progressCapsuleBorder(progress: Double, color: Color, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(
            isActive: false,
            color: color,
            lineWidth: lineWidth,
            cornerRadius: nil,
            progress: CGFloat(progress)
        ))
    }

    /// Determinate **rounded-rectangle** progress border: the stroke fills and the gap
    /// closes as `progress` (0...1) approaches 1.
    func progressRoundedBorder(progress: Double, color: Color, cornerRadius: CGFloat, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(
            isActive: false,
            color: color,
            lineWidth: lineWidth,
            cornerRadius: cornerRadius,
            progress: CGFloat(progress)
        ))
    }
}
