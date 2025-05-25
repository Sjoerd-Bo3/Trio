import SwiftUI

struct DynamicISFProgressView: View {
    let currentDataPoints: Int
    let requiredDataPoints: Int
    
    private var progress: Double {
        guard requiredDataPoints > 0 else { return 0 }
        return min(Double(currentDataPoints) / Double(requiredDataPoints), 1.0)
    }
    
    private var progressPercentage: Int {
        Int(progress * 100)
    }
    
    private var daysOfData: Double {
        // Calculate days based on data points (288 per day)
        Double(currentDataPoints) / 288.0
    }
    
    private var formattedDays: String {
        if daysOfData < 1 {
            let hours = Int(daysOfData * 24)
            return String(localized: "\(hours) hours")
        } else {
            return String(format: "%.1f days", daysOfData)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.orange)
                Text("Dynamic ISF Warmup")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Accumulating Data...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(progressPercentage)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.orange]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("\(formattedDays) of data collected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("7 days required")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if progress >= 1.0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Dynamic ISF is ready to use!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// Preview
struct DynamicISFProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // No data
            DynamicISFProgressView(currentDataPoints: 0, requiredDataPoints: 1714)
            
            // Partial data (3 days)
            DynamicISFProgressView(currentDataPoints: 864, requiredDataPoints: 1714)
            
            // Almost ready (6.5 days)
            DynamicISFProgressView(currentDataPoints: 1872, requiredDataPoints: 1714)
            
            // Ready
            DynamicISFProgressView(currentDataPoints: 1714, requiredDataPoints: 1714)
        }
        .padding()
    }
}