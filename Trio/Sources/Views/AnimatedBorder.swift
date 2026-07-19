//
// This file is the shared base for the animated borders: the CoreAnimation
// engine (`DashedSpinnerBorderView`) and the `AnimatedBorder` modifier.
// Capsule-shaped helpers live in CapsuleBorder.swift; rounded-rectangle "panel"
// helpers (incl. the segmented distribution border) live in PanelBorder.swift.
//
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
    /// Faint full-perimeter track, shown behind the fill in determinate progress mode
    /// so the filled vs. unfilled portion reads at a glance.
    private let track = CAShapeLayer()
    /// Primary stroke: the whole perimeter in spin/solid mode, the **top** half in
    /// determinate mode.
    private let shape = CAShapeLayer()
    /// Determinate-only **bottom** half, mirroring `shape` so progress fills the top and
    /// bottom edges symmetrically left → right.
    private let shapeBottom = CAShapeLayer()
    private var spinning = false
    private var perimeter: CGFloat = 0
    // Cached geometry so applyMode() can reassign layer paths without a relayout.
    private var fullPath: CGPath?
    private var topHalfPath: CGPath?
    private var bottomHalfPath: CGPath?

    var strokeColor: UIColor = .systemGray { didSet { applyColors() } }
    var lineWidth: CGFloat = 2 {
        didSet {
            shape.lineWidth = lineWidth
            shapeBottom.lineWidth = lineWidth
            track.lineWidth = lineWidth
            setNeedsLayout()
        }
    }
    /// `nil` → capsule (corner radius = half the shorter side).
    var cornerRadius: CGFloat? { didSet { setNeedsLayout() } }
    /// Share of the perimeter occupied by the moving gap (0...1).
    var gapFraction: CGFloat = 0.3
    var spinDuration: CFTimeInterval = 1.333
    /// Non-nil switches the view to a **determinate** progress meter (0...1): a bright
    /// stroke fills the top and bottom edges symmetrically left → right as it nears 1.
    /// `nil` → indeterminate spinning gap (driven by `setSpinning`).
    var progress: CGFloat? { didSet { applyMode() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for sublayer in [track, shape, shapeBottom] {
            sublayer.fillColor = UIColor.clear.cgColor
            sublayer.lineCap = .round
            sublayer.lineWidth = lineWidth
            layer.addSublayer(sublayer)
        }
        track.isHidden = true
        shapeBottom.isHidden = true
        applyColors()
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

    private func applyColors() {
        if progress != nil {
            // Determinate progress: a bright fill over a faint full-perimeter track.
            shape.strokeColor = strokeColor.cgColor
            shapeBottom.strokeColor = strokeColor.cgColor
            track.strokeColor = strokeColor.withAlphaComponent(0.18).cgColor
        } else {
            shape.strokeColor = strokeColor.withAlphaComponent(0.4).cgColor
        }
    }

    /// Full rounded-rect perimeter (used for the track, the spin, and the solid border).
    private func roundedRectPath(in rect: CGRect, radius r: CGFloat) -> CGPath {
        UIBezierPath(roundedRect: rect, cornerRadius: r).cgPath
    }

    /// Top half of the perimeter, from the left-edge midpoint up-and-over to the
    /// right-edge midpoint — so `strokeEnd` fills it left → right along the top.
    private func topHalfPath(in rect: CGRect, radius r: CGFloat) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path.cgPath
    }

    /// Bottom half of the perimeter, from the left-edge midpoint down-and-over to the
    /// right-edge midpoint — so `strokeEnd` fills it left → right along the bottom.
    private func bottomHalfPath(in rect: CGRect, radius r: CGFloat) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .pi, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path.cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for sublayer in [track, shape, shapeBottom] { sublayer.frame = bounds }
        let inset = lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(cornerRadius ?? min(rect.width, rect.height) / 2, min(rect.width, rect.height) / 2)
        fullPath = roundedRectPath(in: rect, radius: radius)
        topHalfPath = topHalfPath(in: rect, radius: radius)
        bottomHalfPath = bottomHalfPath(in: rect, radius: radius)
        track.path = fullPath
        // Rounded-rect perimeter: the straight segments + the four quarter-circle corners.
        perimeter = 2 * (rect.width - 2 * radius) + 2 * (rect.height - 2 * radius) + 2 * .pi * radius
        applyMode()
    }

    func setSpinning(_ on: Bool) {
        guard on != spinning else { return }
        spinning = on
        applyMode()
    }

    /// Picks the rendering mode from the current state: determinate progress meter
    /// when `progress` is set, otherwise the indeterminate spin / solid border.
    private func applyMode() {
        guard perimeter > 0 else { return }
        applyColors()
        if let progress = progress {
            // Determinate: two mirrored halves fill the top and bottom edges left → right.
            track.isHidden = false
            shapeBottom.isHidden = false
            shape.removeAnimation(forKey: "spin")
            shape.lineDashPattern = nil
            shape.lineDashPhase = 0
            shape.path = topHalfPath
            shapeBottom.path = bottomHalfPath
            let clamped = max(0, min(1, progress))
            // Animate strokeEnd on the render server so progress steps ease smoothly.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            for layer in [shape, shapeBottom] {
                layer.strokeStart = 0
                layer.strokeEnd = clamped
            }
            CATransaction.commit()
        } else if spinning {
            track.isHidden = true
            shapeBottom.isHidden = true
            shape.path = fullPath
            shape.strokeStart = 0
            shape.strokeEnd = 1
            let gap = perimeter * gapFraction
            shape.lineDashPattern = [NSNumber(value: Double(perimeter - gap)), NSNumber(value: Double(gap))]
            reapplyAnimation()
        } else {
            track.isHidden = true
            shapeBottom.isHidden = true
            shape.path = fullPath
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
struct AnimatedBorder: ViewModifier {
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
