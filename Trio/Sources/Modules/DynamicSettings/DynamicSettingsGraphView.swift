import SwiftUI
import Swinject

extension DynamicSettings {
    struct GraphView: View {
        @StateObject private var viewModel: GraphViewModel
        @Environment(\.colorScheme) var colorScheme

        init(resolver: Resolver) {
            let settingsManager = resolver.resolve(SettingsManager.self)!
            let glucoseStorage = resolver.resolve(GlucoseStorage.self)!
            _viewModel = StateObject(wrappedValue: GraphViewModel(
                settingsManager: settingsManager,
                glucoseStorage: glucoseStorage,
                resolver: resolver
            ))
        }

        var body: some View {
            VStack(spacing: 16) {
                // Chart Section
                chartSection

                // Legend Section
                legendSection

                // Playground Button
                playgroundButton
            }
            .sheet(isPresented: $viewModel.showPlayground) { [weak viewModel] in
                if let viewModel = viewModel {
                    PlaygroundView(
                        parameters: $viewModel.parameters,
                        isPresented: $viewModel.showPlayground,
                        units: viewModel.units,
                        currentGlucose: viewModel.currentGlucose,
                        onSave: { parameters in
                            viewModel.saveParameters(parameters)
                        }
                    )
                }
            }
        }

        private var chartSection: some View {
            ISFCurveView(
                parameters: viewModel.parameters,
                units: viewModel.units,
                showLogarithmicCurve: viewModel.showLogarithmicCurve,
                showSigmoidCurve: viewModel.showSigmoidCurve,
                currentGlucose: viewModel.currentGlucose,
                isPlayground: false
            )
        }

        private var legendSection: some View {
            ISFLegendView(
                showLogarithmicCurve: $viewModel.showLogarithmicCurve,
                showSigmoidCurve: $viewModel.showSigmoidCurve,
                activeFormula: viewModel.parameters.activeFormula,
                isPlayground: false
            )
        }

        private var playgroundButton: some View {
            Button(action: viewModel.openPlayground) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Playground")
                            .font(.headline)
                        Text("Adjust parameters and see real-time changes")
                            .font(.caption)
                            .opacity(0.8)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.insulin, Color.insulin.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
