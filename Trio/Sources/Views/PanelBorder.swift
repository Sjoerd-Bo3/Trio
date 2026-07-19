import SwiftUI
import UIKit

// Rounded-rectangle "panel" border helpers. The animated spin / progress borders are built
// on the shared `SpinningCapsuleBorder` engine in SpinningCapsuleBorder.swift; the segmented
// distribution border is pure SwiftUI. Used by the bolus progress card and the
// time-in-range stats panel.
extension View {
    /// Animated, spinning **rounded-rectangle** border that activates with `isActive`.
    func spinningRoundedBorder(isActive: Bool, color: Color, cornerRadius: CGFloat, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(isActive: isActive, color: color, lineWidth: lineWidth, cornerRadius: cornerRadius))
    }

    /// Determinate **rounded-rectangle** progress border: a bright stroke fills the top and
    /// bottom edges symmetrically left → right as `progress` (0...1) approaches 1.
    func progressRoundedBorder(progress: Double, color: Color, cornerRadius: CGFloat, lineWidth: CGFloat = 2) -> some View {
        modifier(SpinningCapsuleBorder(
            isActive: false,
            color: color,
            lineWidth: lineWidth,
            cornerRadius: cornerRadius,
            progress: CGFloat(progress)
        ))
    }

    /// Multi-segment **rounded-rectangle** border: the given fractions are laid out left → right
    /// along the top and bottom edges (mirrored), each in its own colour — the same edge geometry
    /// as `progressRoundedBorder`, but a whole distribution instead of a single fill. Fractions are
    /// normalised, so they need not sum to exactly 1.
    func segmentedRoundedBorder(
        segments: [(color: Color, fraction: CGFloat)],
        cornerRadius: CGFloat,
        lineWidth: CGFloat = 3
    ) -> some View {
        modifier(SegmentedRoundedBorder(segments: segments, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

/// One half (top or bottom) of a rounded-rect perimeter, traced left-edge-midpoint →
/// over the corner(s) → right-edge-midpoint, matching `DashedSpinnerBorderView`'s
/// `topHalfPath`/`bottomHalfPath` so `.trim` parametrises left → right.
private struct RoundedRectEdge: Shape {
    enum Edge { case top, bottom }
    let edge: Edge
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return Path() }
        let radius = min(cornerRadius, min(r.width, r.height) / 2)
        let bezier = UIBezierPath()
        switch edge {
        case .top:
            bezier.move(to: CGPoint(x: r.minX, y: r.midY))
            bezier.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
            bezier.addArc(withCenter: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
            bezier.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
            bezier.addArc(withCenter: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
            bezier.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        case .bottom:
            bezier.move(to: CGPoint(x: r.minX, y: r.midY))
            bezier.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
            bezier.addArc(withCenter: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: .pi, endAngle: .pi / 2, clockwise: false)
            bezier.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY))
            bezier.addArc(withCenter: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: .pi / 2, endAngle: 0, clockwise: false)
            bezier.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        }
        return Path(bezier.cgPath)
    }
}

/// Draws a distribution (e.g. time-in-range) as the border of a rounded rectangle:
/// each segment occupies its normalised fraction of the top **and** bottom edges,
/// left → right, in its own colour.
struct SegmentedRoundedBorder: ViewModifier {
    let segments: [(color: Color, fraction: CGFloat)]
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 3

    /// Cumulative [start, end] fractions (0...1) per segment, normalised.
    private var ranges: [(color: Color, start: CGFloat, end: CGFloat)] {
        let total = max(segments.reduce(0) { $0 + max($1.fraction, 0) }, 0.0001)
        var acc: CGFloat = 0
        var out: [(color: Color, start: CGFloat, end: CGFloat)] = []
        for seg in segments {
            let start = acc
            let end = min(acc + max(seg.fraction, 0) / total, 1)
            out.append((color: seg.color, start: start, end: end))
            acc = end
        }
        return out
    }

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                ForEach(Array(ranges.enumerated()), id: \.offset) { _, seg in
                    let style = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    RoundedRectEdge(edge: .top, cornerRadius: cornerRadius, lineWidth: lineWidth)
                        .trim(from: seg.start, to: seg.end)
                        .stroke(seg.color, style: style)
                    RoundedRectEdge(edge: .bottom, cornerRadius: cornerRadius, lineWidth: lineWidth)
                        .trim(from: seg.start, to: seg.end)
                        .stroke(seg.color, style: style)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
