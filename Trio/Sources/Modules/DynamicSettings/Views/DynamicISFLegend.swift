import SwiftUI

extension DynamicSettings {
    struct ISFLegendView: View {
        @Binding var showLogarithmicCurve: Bool
        @Binding var showSigmoidCurve: Bool
        let activeFormula: DynamicSensitivityType
        let isPlayground: Bool

        init(
            showLogarithmicCurve: Binding<Bool>,
            showSigmoidCurve: Binding<Bool>,
            activeFormula: DynamicSensitivityType,
            isPlayground: Bool = false
        ) {
            _showLogarithmicCurve = showLogarithmicCurve
            _showSigmoidCurve = showSigmoidCurve
            self.activeFormula = activeFormula
            self.isPlayground = isPlayground
        }

        private var legendItems: [LegendItem] {
            [
                LegendItem(
                    label: "Logarithmic",
                    color: .blue,
                    isVisible: showLogarithmicCurve
                ),
                LegendItem(
                    label: "Sigmoid",
                    color: .red,
                    isVisible: showSigmoidCurve
                )
            ]
        }

        var body: some View {
            VStack(alignment: .leading, spacing: isPlayground ? 16 : 12) {
                if isPlayground {
                    Text("Curve Visibility")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                HStack(spacing: isPlayground ? 24 : 16) {
                    // Logarithmic curve legend
                    legendButton(
                        label: "Logarithmic",
                        color: .blue,
                        isVisible: showLogarithmicCurve,
                        isActive: activeFormula == .logarithmic
                    ) {
                        showLogarithmicCurve.toggle()
                    }

                    // Sigmoid curve legend
                    legendButton(
                        label: "Sigmoid",
                        color: .red,
                        isVisible: showSigmoidCurve,
                        isActive: activeFormula == .sigmoid
                    ) {
                        showSigmoidCurve.toggle()
                    }

                    if !isPlayground {
                        Spacer()
                    }
                }

                if isPlayground {
                    Text("Tap to show/hide curves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, isPlayground ? 0 : 16)
            .padding(.vertical, isPlayground ? 0 : 8)
        }

        private func legendButton(
            label: String,
            color: Color,
            isVisible: Bool,
            isActive: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    // Color indicator
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isVisible ? color : Color.secondary.opacity(0.3))
                        .frame(width: isPlayground ? 20 : 16, height: isPlayground ? 4 : 3)

                    // Label
                    Text(label)
                        .font(isPlayground ? .body : .caption)
                        .foregroundColor(isVisible ? .primary : .secondary)
                        .fontWeight(isActive ? .semibold : .regular)

                    // Active indicator
                    if isActive && !isPlayground {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(color)
                    }
                }
                .padding(.horizontal, isPlayground ? 12 : 8)
                .padding(.vertical, isPlayground ? 8 : 4)
                .background(
                    RoundedRectangle(cornerRadius: isPlayground ? 8 : 6)
                        .fill(Color.secondary.opacity(isVisible ? 0.1 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPlayground ? 8 : 6)
                        .stroke(isActive ? color : Color.clear, lineWidth: isActive ? 2 : 0)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
